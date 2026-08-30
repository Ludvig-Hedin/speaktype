import Foundation

/// Single place that turns Whisper output into what we paste, save, and show—after optional writing polish.
enum TranscriptionFinalizer {

    static func finalizeTranscript(rawTranscript: String) async -> String {
        let configuration = WritingPolishConfiguration.loadFromUserDefaults()
        return await WritingPolishService.polish(
            rawTranscript: rawTranscript,
            configuration: configuration
        )
    }

    static func willPolishNextTranscript() -> Bool {
        let configuration = WritingPolishConfiguration.loadFromUserDefaults()
        return WritingPolishService.willPolish(configuration: configuration)
    }

    static func summarizeTranscript(_ transcript: String) async throws -> String {
        let configuration = WritingPolishConfiguration.loadFromUserDefaults()
        let provider = WritingPolishService.effectiveProvider(configuration)
        guard provider.isRemote, provider.hasKey() else {
            throw RemoteCleanupClient.CleanupError.missingKey
        }
        return try await RemoteCleanupClient.summarize(
            provider: provider,
            modelID: configuration.cleanupModelID,
            transcript: transcript
        )
    }

    static func polishTranscriptOnDemand(_ transcript: String) async -> String {
        var configuration = WritingPolishConfiguration.loadFromUserDefaults()
        configuration.isEnabled = true
        return await WritingPolishService.polish(
            rawTranscript: transcript,
            configuration: configuration
        )
    }
}
