import XCTest
@testable import speaktype

final class WritingPolishModelsTests: XCTestCase {

    func testPresetInstructionsAreNonEmpty() {
        for preset in WritingPolishPreset.allCases {
            let withFillers = preset.styleInstructions(removeFillers: true)
            let withoutFillers = preset.styleInstructions(removeFillers: false)
            XCTAssertFalse(withFillers.isEmpty, preset.rawValue)
            XCTAssertFalse(withoutFillers.isEmpty, preset.rawValue)
            XCTAssertTrue(withFillers.contains("filler"))
            XCTAssertFalse(withoutFillers.contains("filler"))
            if preset == .bullets {
                XCTAssertTrue(withFillers.lowercased().contains("bullet"))
            }
        }
    }

    func testLoadFromUserDefaultsUsesRegisteredDefaults() {
        let suiteName = "test.WritingPolishModels.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        var configuration = WritingPolishConfiguration.loadFromUserDefaults(defaults)
        XCTAssertTrue(configuration.isEnabled)
        XCTAssertEqual(configuration.preset, .clean)
        XCTAssertTrue(configuration.removeFillers)
        XCTAssertEqual(configuration.ollamaBaseURL, WritingPolishUserDefaults.defaultOllamaBaseURL)
        XCTAssertEqual(configuration.ollamaModel, WritingPolishUserDefaults.defaultOllamaModel)
        XCTAssertEqual(configuration.ollamaTemperature, 0.2, accuracy: 0.001)

        defaults.set(false, forKey: WritingPolishUserDefaults.enabledKey)
        defaults.set(WritingPolishPreset.professional.rawValue, forKey: WritingPolishUserDefaults.presetKey)
        defaults.set(false, forKey: WritingPolishUserDefaults.removeFillersKey)
        defaults.set("http://localhost:11434", forKey: WritingPolishUserDefaults.ollamaBaseURLKey)
        defaults.set("phi4-mini:3.8b-q4_K_M", forKey: WritingPolishUserDefaults.ollamaModelKey)
        defaults.set(0.35, forKey: WritingPolishUserDefaults.ollamaTemperatureKey)

        configuration = WritingPolishConfiguration.loadFromUserDefaults(defaults)
        XCTAssertFalse(configuration.isEnabled)
        XCTAssertEqual(configuration.preset, .professional)
        XCTAssertFalse(configuration.removeFillers)
        XCTAssertEqual(configuration.ollamaBaseURL, "http://localhost:11434")
        XCTAssertEqual(configuration.ollamaModel, "phi4-mini:3.8b-q4_K_M")
        XCTAssertEqual(configuration.ollamaTemperature, 0.35, accuracy: 0.001)
    }

    func testOllamaBaseURLNormalization() {
        XCTAssertEqual(OllamaPolishClient.normalizeBaseURL(""), WritingPolishUserDefaults.defaultOllamaBaseURL)
        XCTAssertEqual(OllamaPolishClient.normalizeBaseURL("127.0.0.1:11434"), "http://127.0.0.1:11434")
        XCTAssertEqual(
            OllamaPolishClient.normalizeBaseURL("http://127.0.0.1:11434///"),
            "http://127.0.0.1:11434"
        )
    }
}
