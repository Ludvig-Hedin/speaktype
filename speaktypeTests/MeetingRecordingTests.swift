import AVFoundation
import XCTest
import os
@testable import speaktype

final class MeetingRecordingTests: XCTestCase {
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
        XCTAssertEqual(first.end, 9600000)
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
            for _ in 0..<601 { try output.write(from: buffer) }
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
        XCTAssertEqual(partial.meetingFrame, MeetingFiles.segmentFrames)
        XCTAssertTrue(partial.isFailed)
        await history.transcribeMeeting(partial, automatically: false) { segment, _, _ in
            calls += 1
            let remaining = try AVAudioFile(forReading: segment)
            XCTAssertLessThan(remaining.length, 18000)
            return outcome("Last part")
        }
        let finished = try XCTUnwrap(DictationRecoveryStore.live.load().first { $0.id == id })
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(finished.transcript, "First part\nLast part")
        XCTAssertFalse(finished.isFailed)
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

    func testIsolatedTracksMixAndSegment() throws {
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
    }
}
