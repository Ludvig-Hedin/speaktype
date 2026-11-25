import AVFoundation
import CoreAudio
import AudioToolbox
import os

nonisolated struct MeetingAudioError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private nonisolated func checkAudio(_ status: OSStatus, line: UInt = #line) throws {
    guard status == noErr else {
        Logger().error("Meeting capture failed at line \(line): \(status)")
        throw MeetingAudioError(message: "Audio capture failed (\(status)).")
    }
}

/// Core Audio owns the conversion and a bounded asynchronous disk writer. CAF supports
/// an unknown data-chunk length while open, allowing recovery after an abrupt exit.
nonisolated final class MeetingTrack: @unchecked Sendable {
    private let file: ExtAudioFileRef
    let status = OSAllocatedUnfairLock(initialState: OSStatus(noErr))
    let heardSignal = OSAllocatedUnfairLock(initialState: false)
    let level = OSAllocatedUnfairLock(initialState: Float.zero)
    private let offsetURL: URL
    private let origin: Double
    private let receivedTimestamp = OSAllocatedUnfairLock(initialState: false)
    private let offsetQueue = DispatchQueue(label: "Taly.meetingTrackStart")
    init(url: URL, input: AudioStreamBasicDescription, origin: Double) throws {
        self.origin = origin
        offsetURL = url.deletingPathExtension().appendingPathExtension("offset")
        try JSONEncoder().encode(Int64(0)).write(to: offsetURL, options: .atomic)
        var format = AudioStreamBasicDescription(mSampleRate: MeetingFiles.rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, mBytesPerPacket: 2,
            mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var handle: ExtAudioFileRef?
        try checkAudio(ExtAudioFileCreateWithURL(url as CFURL, kAudioFileCAFType, &format,
                                                 nil, 0, &handle))
        file = handle!
        var client = input
        try checkAudio(ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat,
                                               UInt32(MemoryLayout.size(ofValue: client)), &client))
        try checkAudio(ExtAudioFileWriteAsync(file, 0, nil))
    }

    func append(_ frames: UInt32, _ buffers: UnsafePointer<AudioBufferList>, hostTime: UInt64) {
        guard frames > 0 else { return }
        if hostTime > 0, receivedTimestamp.withLock({ seen in
            if seen { return false }
            seen = true
            return true
        }) {
            let seconds = AVAudioTime.seconds(forHostTime: hostTime) - origin
            let offset = Int64(max(0, seconds) * MeetingFiles.rate)
            offsetQueue.async { [offsetURL, status] in
                do { try JSONEncoder().encode(offset).write(to: offsetURL, options: .atomic) }
                catch { status.withLock { $0 = kAudioFileUnspecifiedError } }
            }
        }
        let result = ExtAudioFileWriteAsync(file, frames, buffers)
        if result != noErr { status.withLock { $0 = result } }
        if let data = buffers.pointee.mBuffers.mData {
            let samples = data.assumingMemoryBound(to: Float.self)
            let count = min(Int(frames), Int(buffers.pointee.mBuffers.mDataByteSize) / 4)
            var peak: Float = 0
            for i in stride(from: 0, to: count, by: 16) { peak = max(peak, abs(samples[i])) }
            let measured = min(1, peak * 4)
            level.withLock { $0 = measured }
            if measured > 0.001 { heardSignal.withLock { $0 = true } }
        }
    }
    deinit {
        ExtAudioFileDispose(file)
        offsetQueue.sync {}
    }
}

@available(macOS 14.2, *)
private nonisolated final class MeetingSystemTap {
    var tap = AudioObjectID(kAudioObjectUnknown)
    var aggregate = AudioObjectID(kAudioObjectUnknown)
    var proc: AudioDeviceIOProcID?
    var track: MeetingTrack?

    func start(folder: URL, origin: TimeInterval) throws {
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.name = "Taly meeting"
        description.isPrivate = true
        try checkAudio(AudioHardwareCreateProcessTap(description, &tap))
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout.size(ofValue: format))
        try checkAudio(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format))
        let properties: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Taly meeting",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                              kAudioSubTapDriftCompensationKey: true]]
        ]
        try checkAudio(AudioHardwareCreateAggregateDevice(properties as CFDictionary, &aggregate))
        let writer = try MeetingTrack(url: folder.appendingPathComponent("system.caf"), input: format, origin: origin)
        track = writer
        let bytesPerFrame = format.mBytesPerFrame
        guard bytesPerFrame > 0 else { throw MeetingAudioError(message: "Unsupported system audio format.") }
        try checkAudio(AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { _, input, timestamp, _, _ in
            writer.append(input.pointee.mBuffers.mDataByteSize / bytesPerFrame, input, hostTime: timestamp.pointee.mHostTime)
        })
        try checkAudio(AudioDeviceStart(aggregate, proc))
    }

    deinit {
        if let proc {
            AudioDeviceStop(aggregate, proc)
            AudioDeviceDestroyIOProcID(aggregate, proc)
        }
        if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate) }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
    }
}

/// Hardware setup and teardown run on a worker, never in SwiftUI. After start the
/// callback owns its writer and only the locked meters are sampled by the UI.
nonisolated final class MeetingCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var mic: MeetingTrack?
    private var system: AnyObject?
    private var systemMeter: (@Sendable () -> Float)?
    private var installed = false
    private(set) var micOnly = true
    var systemHasSignal: Bool {
        if #available(macOS 14.2, *), let tap = system as? MeetingSystemTap {
            return tap.track?.heardSignal.withLock { $0 } == true
        }
        return false
    }
    var writeFailed: Bool {
        if mic?.status.withLock({ $0 != noErr }) == true { return true }
        if #available(macOS 14.2, *), let tap = system as? MeetingSystemTap {
            return tap.track?.status.withLock { $0 != noErr } == true
        }
        return false
    }
    var level: Float { max(mic?.level.withLock { $0 } ?? 0, systemMeter?() ?? 0) }

    func start(folder: URL, deviceUID: String?) throws {
        let input = engine.inputNode
        if let deviceUID, let unit = input.audioUnit {
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var device = AudioDeviceID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout.size(ofValue: device))
            let uid = deviceUID as CFString
            try withExtendedLifetime(uid) {
                var reference = Unmanaged.passUnretained(uid)
                try checkAudio(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                    UInt32(MemoryLayout.size(ofValue: reference)), &reference, &size, &device))
            }
            try checkAudio(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                               kAudioUnitScope_Global, 0, &device, size))
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MeetingAudioError(message: "Selected microphone is unavailable.")
        }
        let origin = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        let writer = try MeetingTrack(url: folder.appendingPathComponent("mic.caf"),
                                      input: format.streamDescription.pointee, origin: origin)
        mic = writer
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, time in
            writer.append(buffer.frameLength, buffer.audioBufferList, hostTime: time.hostTime)
        }
        installed = true
        try engine.start()
        if #available(macOS 14.2, *) {
            let capture = MeetingSystemTap()
            do {
                try capture.start(folder: folder, origin: origin)
                system = capture
                systemMeter = { [meter = capture.track?.level] in meter?.withLock { $0 } ?? 0 }
                micOnly = false
            } catch {
                Logger().warning("System audio unavailable: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func stop() {
        engine.stop()
        if installed { engine.inputNode.removeTap(onBus: 0); installed = false }
        system = nil
        mic = nil
    }
}
