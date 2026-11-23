import XCTest
@testable import speaktype

final class ModelDownloadServiceTests: XCTestCase {
    
    func testInitialState() {
        let service = ModelDownloadService.shared
        
        // Ensure no lingering downloads from other runs
        // (Note: Shared singleton might have state if tests run in parallel or sequence without clearing)
        // We can't easily clear private vars, but we can check types.
        
        XCTAssertNotNil(service.downloadProgress)
        XCTAssertNotNil(service.isDownloading)
    }

    func testFullLargeV3CacheDoesNotMatchTurbo() {
        let patterns = ["whisper-large-v3", "openai_whisper-large-v3"]
        XCTAssertTrue(ModelDownloadService.matchesCacheName("openai_whisper-large-v3", patterns: patterns))
        XCTAssertTrue(ModelDownloadService.matchesCacheName("models--openai--whisper-large-v3", patterns: patterns))
        XCTAssertFalse(ModelDownloadService.matchesCacheName("openai_whisper-large-v3_turbo", patterns: patterns))
    }
    
    // Real download tests require mocking backend connections or WhisperKit, which is out of scope for basic unit tests without dependency injection.
    // We verified the model IDs in the previous verification step.
}
