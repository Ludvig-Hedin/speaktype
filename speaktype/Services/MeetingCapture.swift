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
    private var file: ExtAudioFileRef?
    private let ioLock = NSLock()
    private let inputRate: Double
    private var inputFrames: Int64 = 0
    private var lastAnchor: Int64 = -1
    let lastAppend = OSAllocatedUnfairLock(initialState: mach_absolute_time())
    let status = OSAllocatedUnfairLock(initialState: OSStatus(noErr))
    let heardSignal = OSAllocatedUnfairLock(initialState: false)
    let level = OSAllocatedUnfairLock(initialState: Float.zero)
    private let offsetURL: URL
    private let origin: Double
    private let anchorsURL: URL
    private let offsetQueue = DispatchQueue(label: "Taly.meetingTrackStart")
    init(url: URL, input: AudioStreamBasicDescription, origin: Double) throws {
        self.origin = origin
        inputRate = input.mSampleRate
        anchorsURL = url.deletingPathExtension().appendingPathExtension("anchors")
        offsetURL = url.deletingPathExtension().appendingPathExtension("offset")
        try JSONEncoder().encode(Int64(0)).write(to: offsetURL, options: .atomic)
        var format = AudioStreamBasicDescription(mSampleRate: MeetingFiles.rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, mBytesPerPacket: 2,
            mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var handle: ExtAudioFileRef?
        try checkAudio(ExtAudioFileCreateWithURL(url as CFURL, kAudioFileCAFType, &format,
                                                 nil, 0, &handle))
        let file = handle!
        self.file = file
        var client = input
        try checkAudio(ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat,
                                               UInt32(MemoryLayout.size(ofValue: client)), &client))
        try checkAudio(ExtAudioFileWriteAsync(file, 0, nil))
    }

    func append(_ frames: UInt32, _ buffers: UnsafePointer<AudioBufferList>, hostTime: UInt64) {
        guard frames > 0 else { return }
        ioLock.lock()
        defer { ioLock.unlock() }
        guard let file else { return }
        lastAppend.withLock { $0 = mach_absolute_time() }
        if hostTime > 0, lastAnchor < 0 || inputFrames - lastAnchor >= Int64(inputRate * 5) {
            let first = lastAnchor < 0
            lastAnchor = inputFrames
            let local = Int64((Double(inputFrames) * MeetingFiles.rate / inputRate).rounded())
            let seconds = AVAudioTime.seconds(forHostTime: hostTime) - origin
            let timeline = Int64((max(0, seconds) * MeetingFiles.rate).rounded())
            offsetQueue.async { [offsetURL, anchorsURL, status] in
                do {
                    if first { try JSONEncoder().encode(timeline).write(to: offsetURL, options: .atomic) }
                    let line = Data("\(local) \(timeline)\n".utf8)
                    if first {
                        try line.write(to: anchorsURL, options: .atomic)
                    } else {
                        let handle = try FileHandle(forWritingTo: anchorsURL)
                        defer { try? handle.close() }
                        try handle.seekToEnd()
                        try handle.write(contentsOf: line)
                    }
                } catch { status.withLock { $0 = kAudioFileUnspecifiedError } }
            }
        }
        inputFrames += Int64(frames)
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
    func close() {
        ioLock.lock()
        defer { ioLock.unlock() }
        guard let file else { return }
        self.file = nil
        let result = ExtAudioFileDispose(file)
        if result != noErr { status.withLock { $0 = result } }
        offsetQueue.sync {}
    }
    deinit { close() }
}

@available(macOS 14.2, *)
private nonisolated final class MeetingSystemTap {
    var tap = AudioObjectID(kAudioObjectUnknown)
    var aggregate = AudioObjectID(kAudioObjectUnknown)
    var proc: AudioDeviceIOProcID?
    var track: MeetingTrack?

    private var formatListener: AudioObjectPropertyListenerBlock?
    private let listenerQueue = DispatchQueue(label: "Taly.tapFormat")
    let changed = OSAllocatedUnfairLock(initialState: false)

    func start(url: URL, origin: TimeInterval) throws {
        var translation = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var pid = getpid()
        var ownProcess = AudioObjectID(kAudioObjectUnknown)
        var processSize = UInt32(MemoryLayout.size(ofValue: ownProcess))
        try checkAudio(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &translation,
            UInt32(MemoryLayout.size(ofValue: pid)), &pid, &processSize, &ownProcess))
        guard ownProcess != kAudioObjectUnknown else { throw MeetingAudioError(message: "Taly could not identify its audio process.") }
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [ownProcess])
        description.name = "Taly meeting"
        description.isPrivate = true
        try checkAudio(AudioHardwareCreateProcessTap(description, &tap))
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let properties: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Taly meeting",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                              kAudioSubTapDriftCompensationKey: true]]
        ]
        try checkAudio(AudioHardwareCreateAggregateDevice(properties as CFDictionary, &aggregate))
        // Creating the aggregate can itself negotiate a format. Observe subsequent changes
        // and read the negotiated format before installing the IO callback.
        let listener: AudioObjectPropertyListenerBlock = { [changed] _, _ in changed.withLock { $0 = true } }
        try checkAudio(AudioObjectAddPropertyListenerBlock(tap, &address, listenerQueue, listener))
        formatListener = listener
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout.size(ofValue: format))
        try checkAudio(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format))
        let writer = try MeetingTrack(url: url, input: format, origin: origin)
        track = writer
        let bytesPerFrame = format.mBytesPerFrame
        guard bytesPerFrame > 0 else { throw MeetingAudioError(message: "Unsupported system audio format.") }
        try checkAudio(AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { [changed] _, input, timestamp, _, _ in
            guard !changed.withLock({ $0 }) else { return }
            writer.append(input.pointee.mBuffers.mDataByteSize / bytesPerFrame, input, hostTime: timestamp.pointee.mHostTime)
        })
        try checkAudio(AudioDeviceStart(aggregate, proc))
    }

    func stop() {
        if let formatListener {
            var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(tap, &address, listenerQueue, formatListener)
            self.formatListener = nil
        }
        if let proc {
            AudioDeviceStop(aggregate, proc)
            AudioDeviceDestroyIOProcID(aggregate, proc)
            self.proc = nil
        }
        if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate) }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        aggregate = kAudioObjectUnknown
        tap = kAudioObjectUnknown
        track?.close()
    }
    deinit { stop() }
}

/// Hardware setup and teardown run on a worker, never in SwiftUI. After start the
/// callback owns its writer and only the locked meters are sampled by the UI.
nonisolated final class MeetingCapture: @unchecked Sendable {
    private var engine = AVAudioEngine()
    private var mic: MeetingTrack?
    private var system: AnyObject?
    private var installed = false
    private var observer: NSObjectProtocol?
    private var defaultInputListener: AudioObjectPropertyListenerBlock?
    private let deviceQueue = DispatchQueue(label: "Taly.defaultInput")
    private var defaultInputAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    private var micChanged = OSAllocatedUnfairLock(initialState: false)
    private var folder: URL!
    private var deviceUID: String?
    private var micPiece = 0
    private var systemPiece = 0
    private var restartSystem = false
    private var stopped = false
    private let origin = AVAudioTime.seconds(forHostTime: mach_absolute_time())
    // Start, monitor and stop can be requested independently; serialize hardware ownership.
    private let control = NSLock()
    private let wakeRequested = OSAllocatedUnfairLock(initialState: false)
    func didWake() { wakeRequested.withLock { $0 = true } }
    struct Health {
        var notice: String?
        var failed = false
    }
    private let snapshot = OSAllocatedUnfairLock(initialState: Health())
    var health: Health { snapshot.withLock { $0 } }
    private let meters = OSAllocatedUnfairLock(initialState: [MeetingTrack]())
    var liveLevel: Float { meters.withLock { $0.map { $0.level.withLock { $0 } }.max() ?? 0 } }
    private func publishMeters() {
        var tracks = [mic].compactMap { $0 }
        if #available(macOS 14.2, *), let track = (system as? MeetingSystemTap)?.track { tracks.append(track) }
        let current = tracks
        meters.withLock { $0 = current }
    }
    private var closeFailed = false

    func start(folder: URL, deviceUID: String?) throws {
        control.lock()
        defer { control.unlock() }
        self.folder = folder
        self.deviceUID = deviceUID
        try startMic()
        if #available(macOS 14.2, *) {
            do { try startSystem(); restartSystem = true }
            catch { Logger().warning("System audio unavailable: \(error.localizedDescription, privacy: .public)") }
        }
        publishMeters()
        snapshot.withLock { $0.notice = restartSystem ? nil : "Microphone only. System audio is unavailable." }
    }

    private func piece(_ kind: String, _ number: Int) -> URL {
        folder.appendingPathComponent(number == 1 ? "\(kind).caf" : "\(kind)-\(number).caf")
    }

    @available(macOS 14.2, *)
    private func startSystem() throws {
        systemPiece += 1
        let tap = MeetingSystemTap()
        try tap.start(url: piece("system", systemPiece), origin: origin)
        system = tap
    }

    static func inputDevice(for uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout.size(ofValue: device))
        let string = uid as CFString
        let result = withExtendedLifetime(string) {
            var reference = Unmanaged.passUnretained(string)
            return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout.size(ofValue: reference)), &reference, &size, &device)
        }
        return result == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private func startMic() throws {
        micPiece += 1
        engine = AVAudioEngine()
        let input = engine.inputNode
        if let deviceUID, var device = Self.inputDevice(for: deviceUID), let unit = input.audioUnit {
            try checkAudio(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout.size(ofValue: device))))
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MeetingAudioError(message: "Selected microphone is unavailable.")
        }
        let writer = try MeetingTrack(url: piece("mic", micPiece),
                                      input: format.streamDescription.pointee, origin: origin)
        mic = writer
        micChanged = OSAllocatedUnfairLock(initialState: false)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [micChanged] buffer, time in
            guard buffer.format.sampleRate == format.sampleRate, buffer.format.channelCount == format.channelCount,
                  buffer.format.commonFormat == format.commonFormat, buffer.format.isInterleaved == format.isInterleaved else {
                micChanged.withLock { $0 = true }
                return
            }
            writer.append(buffer.frameLength, buffer.audioBufferList, hostTime: time.hostTime)
        }
        installed = true
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [micChanged] _ in
            micChanged.withLock { $0 = true }
        }
        let listener: AudioObjectPropertyListenerBlock = { [micChanged] _, _ in micChanged.withLock { $0 = true } }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultInputAddress, deviceQueue, listener) == noErr {
            defaultInputListener = listener
        }
        try engine.start()
    }

    private func stopMic() {
        if let defaultInputListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultInputAddress,
                                                  deviceQueue, defaultInputListener)
            self.defaultInputListener = nil
        }
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        engine.stop()
        if installed { engine.inputNode.removeTap(onBus: 0); installed = false }
        mic?.close()
        if mic?.status.withLock({ $0 != noErr }) == true { closeFailed = true }
        mic = nil
    }

    private func stopSystem() {
        if #available(macOS 14.2, *), let tap = system as? MeetingSystemTap {
            tap.stop()
            if tap.track?.status.withLock({ $0 != noErr }) == true { closeFailed = true }
        }
        system = nil
    }

    static func stalled(_ last: UInt64?, now: UInt64) -> Bool {
        guard let last, now >= last else { return last == nil }
        return AVAudioTime.seconds(forHostTime: now - last) > 2
    }

    func poll() -> Health {
        control.lock()
        defer { control.unlock() }
        guard !stopped else { return health }
        let now = mach_absolute_time()
        let woke = wakeRequested.withLock { pending in
            defer { pending = false }
            return pending
        }
        var result = Health()
        if woke || micChanged.withLock({ $0 }) || !engine.isRunning || Self.stalled(mic?.lastAppend.withLock { $0 }, now: now) {
            stopMic()
            do { try startMic() } catch { stopMic() }
            result.notice = "Microphone interrupted. Reconnecting…"
        }
        if #available(macOS 14.2, *), restartSystem {
            let tap = system as? MeetingSystemTap
            if woke || tap?.changed.withLock({ $0 }) == true || Self.stalled(tap?.track?.lastAppend.withLock { $0 }, now: now) {
                stopSystem()
                do { try startSystem() } catch { stopSystem() }
                result.notice = result.notice == nil ? "System audio interrupted. Reconnecting…" : "Audio interrupted. Reconnecting…"
            } else if let track = tap?.track {
                result.failed = track.status.withLock { $0 != noErr }
                if result.notice == nil, !track.heardSignal.withLock({ $0 }),
                   AVAudioTime.seconds(forHostTime: now) - origin > 6 {
                    result.notice = "Only microphone audio detected."
                }
            }
        } else if result.notice == nil {
            result.notice = "Microphone only. System audio is unavailable."
        }
        result.failed = result.failed || closeFailed || mic?.status.withLock { $0 != noErr } == true
        publishMeters()
        let updated = result
        snapshot.withLock { $0 = updated }
        return result
    }

    @discardableResult
    func stop() -> Bool {
        control.lock()
        defer { control.unlock() }
        stopped = true
        meters.withLock { $0.removeAll() }
        stopMic()
        stopSystem()
        return closeFailed
    }
}
