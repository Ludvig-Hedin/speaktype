import XCTest
@testable import speaktype

/// Real network run of the dictation pipeline on a saved recording: compressed upload → cloud
/// transcription → cleanup. Skipped unless `SPEAKTYPE_LIVE_AUDIO` points at a WAV, so CI and
/// normal test runs never spend money or need a key.
final class LivePipelineTests: XCTestCase {
    func testLiveTranscribeAndCleanup() async throws {
        guard let path = ProcessInfo.processInfo.environment["SPEAKTYPE_LIVE_AUDIO"] else {
            throw XCTSkip("Set SPEAKTYPE_LIVE_AUDIO to run")
        }
        let url = URL(fileURLWithPath: path)
        let start = Date()
        let outcome = try await TranscriptionCoordinator.transcribe(audioFile: url, language: "auto")
        let sttTime = Date().timeIntervalSince(start)
        XCTAssertFalse(outcome.text.isEmpty)

        let cleanStart = Date()
        let config = WritingPolishConfiguration.loadFromUserDefaults()
        let cleaned = await WritingPolishService.polish(rawTranscript: outcome.text, configuration: config)
        let cleanTime = Date().timeIntervalSince(cleanStart)

        print("LIVE provider=\(outcome.provider.rawValue) model=\(outcome.modelLabel) stt=\(String(format: "%.2f", sttTime))s cleanup=\(String(format: "%.2f", cleanTime))s cleanupModel=\(config.cleanupModelID)")
        print("LIVE raw: \(outcome.text)")
        print("LIVE clean: \(cleaned)")
        XCTAssertFalse(cleaned.isEmpty)
    }
}
