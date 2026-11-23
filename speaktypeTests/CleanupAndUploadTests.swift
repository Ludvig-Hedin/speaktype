import AVFoundation
import XCTest
@testable import speaktype

final class CleanupAndUploadTests: XCTestCase {

    // MARK: - Answer guard

    func testCleanupGuardRejectsAnswers() {
        XCTAssertFalse(WritingPolishService.isPlausibleCleanup(
            raw: "what's the capital of France", cleaned: "Paris"))
        XCTAssertFalse(WritingPolishService.isPlausibleCleanup(
            raw: "Quickly review the local changes and commit the uncommitted ones please",
            cleaned: String(repeating: "I can't run git commands from here, but here is how. ", count: 6)))
        XCTAssertFalse(WritingPolishService.isPlausibleCleanup(
            raw: "hello there my friend", cleaned: "<transcript>hello</transcript>"))
        XCTAssertFalse(WritingPolishService.isPlausibleCleanup(raw: "hej hej hej hej", cleaned: ""))
    }

    func testCleanupGuardAcceptsRealCleanups() {
        // Self-correction halves the length; still a cleanup.
        XCTAssertTrue(WritingPolishService.isPlausibleCleanup(
            raw: "ok so um send the the report to Anna no wait to Erik on Tuesday",
            cleaned: "Send the report to Erik on Tuesday."))
        XCTAssertTrue(WritingPolishService.isPlausibleCleanup(
            raw: "vad tycker du om det här, är det en bra idé eller inte?",
            cleaned: "Vad tycker du om det här? Är det en bra idé eller inte?"))
        XCTAssertTrue(WritingPolishService.isPlausibleCleanup(raw: "Thank you.", cleaned: "Thank you."))
    }

    // MARK: - Cleanup catalog

    func testDefaultCleanupModelIsInCatalog() {
        XCTAssertNotNil(CleanupModel.model(id: CleanupModel.defaultModelID))
    }

    func testRetiredCleanupSelectionMovesToDefaultOnce() {
        let suite = "CleanupAndUploadTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("openai/gpt-5.6-luna", forKey: WritingPolishUserDefaults.cleanupModelKey)
        CleanupModel.migrateRetiredSelection(defaults)
        XCTAssertEqual(defaults.string(forKey: WritingPolishUserDefaults.cleanupModelKey),
                       CleanupModel.defaultModelID)

        // A later manual pick of a current model is never overridden.
        defaults.set("anthropic/claude-haiku-5.5", forKey: WritingPolishUserDefaults.cleanupModelKey)
        CleanupModel.migrateRetiredSelection(defaults)
        XCTAssertEqual(defaults.string(forKey: WritingPolishUserDefaults.cleanupModelKey),
                       "anthropic/claude-haiku-5.5")
    }

    func testCleanupPromptWrapsTranscript() {
        XCTAssertTrue(RemoteCleanupClient.systemPrompt.contains("<transcript>"))
        XCTAssertTrue(RemoteCleanupClient.systemPrompt.contains("never translate"))
    }

    // MARK: - Upload compression

    func testUploadEncoderShrinksWav() async throws {
        let wav = try makeToneWav(seconds: 5)
        defer { try? FileManager.default.removeItem(at: wav) }

        let m4a = await AudioUploadEncoder.compressedCopy(of: wav)
        let out = try XCTUnwrap(m4a)
        defer { try? FileManager.default.removeItem(at: out) }

        let wavSize = try XCTUnwrap(try wav.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let m4aSize = try XCTUnwrap(try out.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        XCTAssertLessThan(m4aSize * 4, wavSize, "AAC upload should be far smaller than the WAV")

        let duration = try await AVURLAsset(url: out).load(.duration).seconds
        XCTAssertEqual(duration, 5, accuracy: 0.3)
    }

    /// Same format the recorder writes: 16 kHz, mono, 16-bit PCM WAV.
    private func makeToneWav(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tone-\(UUID().uuidString).wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                   channels: 1, interleaved: true)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: .pcmFormatInt16, interleaved: true)
        let frames = AVAudioFrameCount(seconds * 16_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.int16ChannelData![0]
        for i in 0..<Int(frames) {
            samples[i] = Int16(sin(Double(i) * 2 * .pi * 220 / 16_000) * 8_000)
        }
        try file.write(from: buffer)
        return url
    }
}
