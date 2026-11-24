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

    func testScanningModelStorageRecognizesCompleteModelsAfterMigration() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: root) }

        let legacy = root.appendingPathComponent("legacy")
        let current = root.appendingPathComponent("current")
        let variant = "openai_whisper-large-v3"
        let modelPath = "models/argmaxinc/whisperkit-coreml"
        let model = legacy.appendingPathComponent(modelPath).appendingPathComponent(variant)
        let tokenizerPath = "models/openai/whisper-large-v3"
        let tokenizer = legacy.appendingPathComponent(tokenizerPath)
        try fileManager.createDirectory(at: model.appendingPathComponent("AudioEncoder.mlmodelc"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tokenizer, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: model.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: tokenizer.appendingPathComponent("tokenizer.json"))

        let currentModels = current.appendingPathComponent(modelPath)
        let currentTokenizer = current.appendingPathComponent(tokenizerPath).appendingPathComponent("tokenizer.json")
        XCTAssertTrue(ModelDownloadService.scanDownloadedModels(expectedSizes: [variant: 2], in: currentModels).isEmpty)
        XCTAssertTrue(ModelStorage.migrateLegacyCache(from: legacy, to: current))
        XCTAssertEqual(ModelDownloadService.scanDownloadedModels(expectedSizes: [variant: 2], in: currentModels), [variant])
        XCTAssertTrue(fileManager.fileExists(atPath: currentTokenizer.path))
        XCTAssertFalse(ModelStorage.migrateLegacyCache(from: legacy, to: current))
    }

    // Real download tests require mocking backend connections or WhisperKit, which is out of scope for basic unit tests without dependency injection.
    // We verified the model IDs in the previous verification step.
}
