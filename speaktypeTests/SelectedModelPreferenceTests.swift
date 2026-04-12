import XCTest
@testable import speaktype

final class SelectedModelPreferenceTests: XCTestCase {
    func testResolveKeepsValidCurrent() {
        let resolved = SelectedModelPreference.resolveSelection(
            current: "openai_whisper-tiny",
            downloadedVariants: ["openai_whisper-tiny", "openai_whisper-base.en"],
            recommended: "openai_whisper-large-v3_turbo",
            orderedVariants: AIModel.availableModels.map(\.variant),
            isActivelyDownloading: { _ in false }
        )
        XCTAssertEqual(resolved, "openai_whisper-tiny")
    }

    func testResolvePrefersRecommendedWhenDownloaded() {
        let resolved = SelectedModelPreference.resolveSelection(
            current: "",
            downloadedVariants: ["openai_whisper-large-v3_turbo", "openai_whisper-tiny"],
            recommended: "openai_whisper-large-v3_turbo",
            orderedVariants: AIModel.availableModels.map(\.variant),
            isActivelyDownloading: { _ in false }
        )
        XCTAssertEqual(resolved, "openai_whisper-large-v3_turbo")
    }

    func testResolveFallsBackToFirstOrderedDownloadWhenRecommendedMissing() {
        let ordered = AIModel.availableModels.map(\.variant)
        let resolved = SelectedModelPreference.resolveSelection(
            current: "",
            downloadedVariants: ["openai_whisper-tiny"],
            recommended: "openai_whisper-large-v3_turbo",
            orderedVariants: ordered,
            isActivelyDownloading: { _ in false }
        )
        XCTAssertEqual(resolved, "openai_whisper-tiny")
    }

    func testResolvePreservesCurrentWhileDownloadInFlight() {
        let resolved = SelectedModelPreference.resolveSelection(
            current: "openai_whisper-medium",
            downloadedVariants: [],
            recommended: "openai_whisper-large-v3_turbo",
            orderedVariants: AIModel.availableModels.map(\.variant),
            isActivelyDownloading: { $0 == "openai_whisper-medium" }
        )
        XCTAssertEqual(resolved, "openai_whisper-medium")
    }

    func testResolveUsesRecommendedWhenNothingOnDisk() {
        let resolved = SelectedModelPreference.resolveSelection(
            current: "",
            downloadedVariants: [],
            recommended: "openai_whisper-small.en",
            orderedVariants: AIModel.availableModels.map(\.variant),
            isActivelyDownloading: { _ in false }
        )
        XCTAssertEqual(resolved, "openai_whisper-small.en")
    }
}
