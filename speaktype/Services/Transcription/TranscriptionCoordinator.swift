import Foundation

/// Single entry point every transcription call site goes through (mirrors `TranscriptionFinalizer`).
/// Resolves the provider chain for the current mode + machine state and executes it with fallback,
/// so the UI never calls `WhisperService.transcribe` directly.
enum TranscriptionCoordinator {

    enum CoordinatorError: LocalizedError {
        case noProviderAvailable
        var errorDescription: String? {
            "No transcription engine is available. Download a model or add a cloud API key in Settings."
        }
    }

    static func transcribe(audioFile: URL, language: String) async throws -> TranscriptionOutcome {
        let chain = resolveChain()
        guard !chain.isEmpty else { throw CoordinatorError.noProviderAvailable }

        var lastError: Error?
        for kind in chain {
            guard let provider = makeProvider(kind) else { continue }
            do {
                return try await provider.transcribeDetailed(audioFile: audioFile, language: language)
            } catch {
                print("Transcription via \(kind.rawValue) failed, trying fallback: \(error.localizedDescription)")
                lastError = error
                continue
            }
        }
        throw lastError ?? CoordinatorError.noProviderAvailable
    }

    /// Whether the next transcription will go to the cloud — drives the recorder privacy hint.
    static func willUseRemoteNextTranscript() -> (isRemote: Bool, providerLabel: String?) {
        guard let first = resolveChain().first else { return (false, nil) }
        return (first.isRemote, first.isRemote ? first.displayName : nil)
    }

    // MARK: - Internals

    private static func resolveChain() -> [TranscriptionProviderKind] {
        let localVariant = UserDefaults.standard.string(forKey: SelectedModelPreference.storageKey) ?? ""
        let localAvailable = !localVariant.isEmpty
            && (ModelDownloadService.shared.downloadProgress[localVariant] ?? 0) >= 1.0

        let inputs = TranscriptionRouter.Inputs(
            mode: TranscriptionModeUserDefaults.mode,
            localAvailable: localAvailable,
            remoteProvider: TranscriptionModeUserDefaults.selectedRemoteProvider?.providerKind,
            remoteConfigured: TranscriptionModeUserDefaults.isRemoteConfigured
                && TranscriptionModeUserDefaults.selectedRemoteModel != nil,
            networkAvailable: NetworkReachability.shared.isOnline,
            availableRAMGB: SystemMemory.availableMemoryGB(),
            localFootprintGB: localVariant.isEmpty ? 0 : ModelMemoryPolicy.estimatedFootprintGB(variant: localVariant),
            cpuLoadPerCore: SystemMemory.loadAveragePerCore()
        )
        return TranscriptionRouter.resolveChain(inputs)
    }

    private static func makeProvider(_ kind: TranscriptionProviderKind) -> TranscriptionProvider? {
        switch kind {
        case .localWhisper:
            return WhisperService.shared
        case .openAI, .groq:
            guard let provider = TranscriptionModeUserDefaults.selectedRemoteProvider,
                  provider.providerKind == kind,
                  let model = TranscriptionModeUserDefaults.selectedRemoteModel else {
                return nil
            }
            return RemoteTranscriptionClient(provider: provider, model: model)
        }
    }
}
