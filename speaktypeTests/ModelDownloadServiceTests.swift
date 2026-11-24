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

    func testPurgingFullLargeV3PreservesTurboAndQuantizedModels() throws {
        let fileManager = FileManager.default
        let cache = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: cache) }

        let full = cache.appendingPathComponent("openai_whisper-large-v3")
        let legacyFull = cache.appendingPathComponent("models--openai--whisper-large-v3")
        let turbo = cache.appendingPathComponent("openai_whisper-large-v3_turbo")
        let quantized = cache.appendingPathComponent("openai_whisper-large-v3_947MB")
        for folder in [full, legacyFull, turbo, quantized] {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        XCTAssertEqual(ModelDownloadService.purgeModelCaches(variant: full.lastPathComponent, in: [cache]), 2)
        XCTAssertFalse(fileManager.fileExists(atPath: full.path))
        XCTAssertFalse(fileManager.fileExists(atPath: legacyFull.path))
        XCTAssertTrue(fileManager.fileExists(atPath: turbo.path))
        XCTAssertTrue(fileManager.fileExists(atPath: quantized.path))
    }

    // Real download tests require mocking backend connections or WhisperKit, which is out of scope for basic unit tests without dependency injection.
    // We verified the model IDs in the previous verification step.
}
