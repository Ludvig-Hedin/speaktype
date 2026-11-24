import Foundation
import OSLog

/// Single place that turns Whisper output into what we paste, save, and show—after optional writing polish.
enum TranscriptionFinalizer {

    static func finalizeTranscript(rawTranscript: String) async -> String {
        let configuration = WritingPolishConfiguration.loadFromUserDefaults()
        return await polish(rawTranscript, configuration: configuration)
    }

    /// Interactive dictation has a single deadline across cloud cleanup and any local fallback.
    /// Manual cleanup and imports keep their existing request timeouts.
    static func finalizeDictation(
        rawTranscript: String, onPolish: @escaping @MainActor @Sendable () -> Void
    ) async -> String {
        let configuration = WritingPolishConfiguration.loadFromUserDefaults()
        guard configuration.isEnabled else { return rawTranscript }
        return await polishWithinBudget(rawTranscript: rawTranscript, budget: .seconds(8)) {
            if WritingPolishService.willPolish(configuration: configuration) {
                await MainActor.run {
                    if !Task.isCancelled { onPolish() }
                }
            }
            return await WritingPolishService.polish(rawTranscript: rawTranscript, configuration: configuration)
        }
    }

    static func polishWithinBudget(
        rawTranscript: String, budget: Duration,
        polish: @escaping @Sendable () async -> String
    ) async -> String {
        let deadline = ContinuousClock.now + budget
        // Let the caller continue even if a provider is slow to acknowledge cancellation.
        // Neither task writes to History or pastes, so late results are safe to drop.
        let (results, result) = AsyncStream<String?>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let worker = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return }
            let text = await polish()
            result.yield(ContinuousClock.now < deadline && !Task.isCancelled ? text : nil)
            result.finish()
        }
        let timeout = Task.detached(priority: .userInitiated) {
            do { try await Task.sleep(until: deadline, clock: .continuous) }
            catch { return }
            result.yield(nil)
            result.finish()
        }
        defer {
            result.finish()
            worker.cancel()
            timeout.cancel()
        }
        var iterator = results.makeAsyncIterator()
        let first = await iterator.next() ?? nil
        if first == nil, !Task.isCancelled {
            AppLogger.transcription.notice("Dictation cleanup deadline reached; using raw transcript")
        }
        return first ?? rawTranscript
    }

    static func willPolishNextTranscript() async -> Bool {
        let configuration = WritingPolishConfiguration.loadFromUserDefaults()
        return await Task.detached {
            WritingPolishService.willPolish(configuration: configuration)
        }.value
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
        return await polish(transcript, configuration: configuration)
    }

    private static func polish(_ transcript: String, configuration: WritingPolishConfiguration) async -> String {
        let worker = Task.detached(priority: .userInitiated) {
            await WritingPolishService.polish(rawTranscript: transcript, configuration: configuration)
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
