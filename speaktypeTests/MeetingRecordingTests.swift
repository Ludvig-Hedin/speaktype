import AVFoundation
import XCTest
import KeyboardShortcuts
import os
@testable import speaktype

final class MeetingRecordingTests: XCTestCase {
    func testMissingMicrophoneWatchdogAndShortcutConflicts() {
        XCTAssertNil(MeetingCapture.inputDevice(for: "unplugged-\(UUID())"))
        let start = AVAudioTime.hostTime(forSeconds: 10)
        XCTAssertFalse(MeetingCapture.stalled(start, now: AVAudioTime.hostTime(forSeconds: 11.99)))
        XCTAssertTrue(MeetingCapture.stalled(start, now: AVAudioTime.hostTime(forSeconds: 12.01)))
        XCTAssertTrue(HotkeyOption.f13.conflicts(with: .init(.f13, modifiers: [.option])))
        XCTAssertFalse(HotkeyOption.f14.conflicts(with: .init(.f13)))
    }

    func testExplicitCloseDrainsBeforeMixAndIgnoresLateCallback() throws {
        let url = MeetingFiles.mixURL(id: UUID())
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let track = try MeetingTrack(url: folder.appendingPathComponent("mic.caf"), input: format.streamDescription.pointee, origin: 10)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        buffer.floatChannelData![0].update(repeating: 0.5, count: 1024)
        track.append(1024, buffer.audioBufferList, hostTime: AVAudioTime.hostTime(forSeconds: 10.5))
        track.close()
        track.append(1024, buffer.audioBufferList, hostTime: AVAudioTime.hostTime(forSeconds: 11))
        track.close()
        XCTAssertEqual(try MeetingFiles.mix(at: url), 0.564, accuracy: 0.0001)
    }

    func testNewPiecesRebuildExistingMixAndCorrectClockDrift() throws {
        let url = MeetingFiles.mixURL(id: UUID())
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        func source(_ name: String, start: Int, level: Float, pulse: Bool = false) throws {
            let file = try AVAudioFile(forWriting: folder.appendingPathComponent(name + ".caf"), settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000)!
            buffer.frameLength = 16000
            buffer.floatChannelData![0].update(repeating: level, count: 16000)
            if pulse { buffer.floatChannelData![0][8000] = 0.65 }
            try file.write(from: buffer)
            try JSONEncoder().encode(start).write(to: folder.appendingPathComponent(name + ".offset"))
        }
        try source("mic", start: 0, level: 0, pulse: true)
        try Data("0 0\n16000 16160\n".utf8).write(to: folder.appendingPathComponent("mic.anchors"))
        XCTAssertEqual(try MeetingFiles.mix(at: url), 1.01)
        try source("mic-2", start: 32000, level: 0.95)
        try source("system-2", start: 32000, level: 0.95)
        XCTAssertEqual(try MeetingFiles.mix(at: url), 3)
        let mix = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: mix.processingFormat, frameCapacity: 48000)!
        try mix.read(into: buffer)
        let samples = buffer.floatChannelData![0]
        XCTAssertEqual(samples[8000], 0, accuracy: 0.001)
        XCTAssertEqual(samples[8080], 0.65, accuracy: 0.001)
        XCTAssertEqual(samples[24000], 0, accuracy: 0.001)
        XCTAssertGreaterThan(samples[40000], 0.8)
        XCTAssertLessThan(samples[40000], 0.999)
    }

    @MainActor
    func testRecoveryDoesNotHoldHistoryOrNewDictation() async throws {
        let id = UUID()
        let url = MeetingFiles.mixURL(id: id)
        let folder = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DictationRecoveryStore(directory: folder.appendingPathComponent("checkpoints"))
        try store.write(HistoryItem(id: id, date: .now, transcript: "", duration: 0, audioFileURL: url,
                                    failureReason: "Interrupted", isMeeting: true))
        let gate = AsyncStream<Void>.makeStream()
        let entered = expectation(description: "Recovery requested")
        let history = HistoryService(store: store) { _ in
            entered.fulfill()
            for await _ in gate.stream { break }
            return 12
        }
        defer { gate.continuation.finish() }
        await fulfillment(of: [entered], timeout: 3)
        let ready = expectation(description: "History and dictation available during recovery")
        let recording = Task {
            await history.waitForStartup()
            XCTAssertTrue(history.containsDictation(id: id))
            _ = try await history.beginDictation(audioURL: folder.appendingPathComponent("other.wav"), duration: 1, language: "en")
            ready.fulfill()
        }
        await fulfillment(of: [ready], timeout: 3)
        // Delete while the mix is in flight. Finishing recovery must never recreate it.
        await history.deleteItem(id: id, deleteAudioFile: false)
        gate.continuation.finish()
        try await recording.value
        for _ in 0..<100 where history.retryingItemIDs.contains(id) { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(history.containsDictation(id: id))
        XCTAssertFalse(store.load().contains { $0.id == id })
    }

    func testTwoHourRecordingSegmentsAtTenMinutes() throws {
        let url = MeetingFiles.mixURL(id: UUID())
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // A synthetic PCM source exercises two hours of frame positions without real audio.
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: MeetingFiles.rate, channels: 1, interleaved: true)!
        let frames = MeetingFiles.segmentFrames * 12
        func createSource() throws {
            let file = try AVAudioFile(forWriting: folder.appendingPathComponent("mic.caf"), settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16000)!
            buffer.frameLength = 16000
            buffer.floatChannelData![0].update(repeating: 0, count: 16000)
            for _ in 0..<7200 { try file.write(from: buffer) }
        }
        try createSource()
        try Data("0".utf8).write(to: folder.appendingPathComponent("mic.offset"))
        XCTAssertEqual(try MeetingFiles.mix(at: url), 7200)
        let segment = folder.appendingPathComponent("segment.m4a")
        let first = try MeetingFiles.segment(from: url, startingAt: 0, to: segment)
        XCTAssertTrue((9_280_000..<9_600_000).contains(first.end))
        XCTAssertFalse(first.last)
        try FileManager.default.removeItem(at: segment)
        let last = try MeetingFiles.segment(from: url, startingAt: frames - 16000, to: segment)
        XCTAssertEqual(last.end, frames)
        XCTAssertTrue(last.last)
    }

    @MainActor
    func testRetryResumesAfterLastCheckpoint() async throws {
        let history = HistoryService.shared
        let id = UUID()
        let url = MeetingFiles.mixURL(id: id)
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func createRecording() throws {
            let format = AVAudioFormat(standardFormatWithSampleRate: MeetingFiles.rate, channels: 1)!
            let output = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000)!
            buffer.frameLength = 16000
            buffer.floatChannelData![0].update(repeating: 0.1, count: 16000)
            for second in 0..<601 {
                buffer.floatChannelData![0].update(repeating: second == 591 ? 0 : 0.1, count: 16000)
                try output.write(from: buffer)
            }
        }
        try createRecording()
        _ = try await history.beginDictation(audioURL: url, duration: 0, language: "en", meetingID: id)
        XCTAssertFalse(history.containsDictation(id: id))
        history.revealStoppedMeeting(id: id)
        try await history.prepareMeeting(id: id)
        let initial = try XCTUnwrap(history.items.first { $0.id == id })
        func outcome(_ text: String) -> TranscriptionOutcome {
            .init(text: text, provider: .localWhisper, modelLabel: "fixture", audioDuration: nil,
                  estimatedCostUSD: nil, transcriptionTime: 1)
        }
        var calls = 0
        await history.transcribeMeeting(initial, automatically: false) { _, _, _ in
            calls += 1
            if calls == 2 { throw RemoteTranscriptionClient.ClientError.network("Offline", transient: true) }
            return outcome("First part")
        }
        let partial = try XCTUnwrap(DictationRecoveryStore.live.load().first { $0.id == id })
        XCTAssertEqual(partial.transcript, "First part")
        XCTAssertTrue((591 * 16000 ..< 592 * 16000).contains(try XCTUnwrap(partial.meetingFrame)))
        XCTAssertTrue(partial.hasPartialMeetingTranscript)
        await history.transcribeMeeting(partial, automatically: false) { segment, _, _ in
            calls += 1
            let remaining = try AVAudioFile(forReading: segment)
            XCTAssertEqual(remaining.length, 601 * 16000 - (partial.meetingFrame ?? 0), accuracy: 1024)
            return outcome("Last part")
        }
        let finished = try XCTUnwrap(DictationRecoveryStore.live.load().first { $0.id == id })
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(finished.transcript, "First part\nLast part")
        XCTAssertFalse(finished.isFailed)
        XCTAssertFalse(finished.hasPartialMeetingTranscript)
        history.finishDictation(id: id)
        await history.deleteItem(id: id)
    }

    func testInterruptedOpenTrackCanBeRecovered() async throws {
        let folder = MeetingFiles.mixURL(id: UUID()).deletingLastPathComponent()
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        let source = folder.appendingPathComponent("open.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let track = try MeetingTrack(url: source, input: format.streamDescription.pointee, origin: 0)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        buffer.frameLength = 4096
        for channel in 0..<2 { buffer.floatChannelData![channel].update(repeating: 0.2, count: 4096) }
        for _ in 0..<20 {
            track.append(4096, buffer.audioBufferList, hostTime: 0)
            try await Task.sleep(for: .milliseconds(10))
        }
        // Copy while the async file is still open, as if the app exited before disposal.
        try fm.copyItem(at: source, to: folder.appendingPathComponent("mic.caf"))
        XCTAssertEqual(track.status.withLock { $0 }, noErr)
        withExtendedLifetime(track) {}
        try Data("0".utf8).write(to: folder.appendingPathComponent("mic.offset"))
        let duration = try MeetingFiles.mix(at: folder.appendingPathComponent("meeting.wav"))
        XCTAssertGreaterThan(duration, 0.5)
        XCTAssertLessThan(duration, 2)
    }

    func testIsolatedTracksMixAndSegment() async throws {
        XCTAssertEqual(AppStorageIsolation.supportFolderName, "SpeakType-Tests")
        let url = MeetingFiles.mixURL(id: UUID())
        let folder = url.deletingLastPathComponent()
        XCTAssertTrue(folder.path.contains("/SpeakType-Tests/Recordings/"))
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        let format = AVAudioFormat(standardFormatWithSampleRate: MeetingFiles.rate, channels: 1)!
        func writeSource(_ name: String, offset: Int, level: Float) throws {
            let file = try AVAudioFile(forWriting: folder.appendingPathComponent(name + ".caf"), settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000)!
            buffer.frameLength = 16000
            buffer.floatChannelData![0].update(repeating: level, count: 16000)
            try file.write(from: buffer)
            try JSONEncoder().encode(offset).write(to: folder.appendingPathComponent(name + ".offset"))
        }
        try writeSource("mic", offset: 0, level: 0.125)
        try writeSource("system", offset: 8000, level: 0.25)
        XCTAssertEqual(try MeetingFiles.mix(at: url), 1.5)
        let mixed = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: mixed.processingFormat, frameCapacity: 24000)!
        try mixed.read(into: buffer)
        let samples = buffer.floatChannelData![0]
        XCTAssertEqual(samples[0], 0.125, accuracy: 0.001)
        XCTAssertEqual(samples[10000], 0.375, accuracy: 0.001)
        XCTAssertEqual(samples[20000], 0.25, accuracy: 0.001)
        let segment = folder.appendingPathComponent("part.m4a")
        let range = try MeetingFiles.segment(from: url, startingAt: 8000, to: segment)
        XCTAssertEqual(range.end, 24000)
        XCTAssertTrue(range.last)
        let encoded = try AVAudioFile(forReading: segment)
        XCTAssertEqual(encoded.fileFormat.settings[AVFormatIDKey] as? UInt32, kAudioFormatMPEG4AAC)
        XCTAssertEqual(encoded.length, 16000, accuracy: 1024)
        var extensions = [String]()
        let text = try await RemoteTranscriptionClient.uploadWithFormatFallback(segment) { file in
            extensions.append(file.pathExtension)
            if file.pathExtension == "m4a" { throw RemoteTranscriptionClient.ClientError.httpStatus(415) }
            let pcm = try AVAudioFile(forReading: file)
            XCTAssertEqual(pcm.fileFormat.settings[AVFormatIDKey] as? UInt32, kAudioFormatLinearPCM)
            XCTAssertEqual(pcm.length, 16000, accuracy: 1024)
            return "Accepted"
        }
        XCTAssertEqual(text, "Accepted")
        XCTAssertEqual(extensions, ["m4a", "wav"])
    }
}
