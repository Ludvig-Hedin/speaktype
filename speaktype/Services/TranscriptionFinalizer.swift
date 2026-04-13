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
}
