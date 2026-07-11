import Foundation

/// Conforms the existing local engine to `TranscriptionProvider` without touching its core
/// `transcribe(...) -> String` logic (self-heal reload, idle-unload, load coalescing all stay).
extension WhisperService: TranscriptionProvider {
    var kind: TranscriptionProviderKind { .localWhisper }

    func isAvailable() async -> Bool {
        let variant = await MainActor.run {
            UserDefaults.standard.string(forKey: SelectedModelPreference.storageKey) ?? ""
        }
        guard !variant.isEmpty else { return false }
        let progress = await MainActor.run {
            ModelDownloadService.shared.downloadProgress[variant] ?? 0
        }
        return progress >= 1.0
    }

    func transcribeDetailed(audioFile: URL, language: String) async throws -> TranscriptionOutcome {
        let start = Date()
        let text = try await transcribe(audioFile: audioFile, language: language)
        let elapsed = Date().timeIntervalSince(start)

        let variant = await MainActor.run {
            UserDefaults.standard.string(forKey: SelectedModelPreference.storageKey) ?? ""
        }
        let label = AIModel.availableModels.first(where: { $0.variant == variant })?.name
            ?? (variant.isEmpty ? "On-device Whisper" : variant)

        return TranscriptionOutcome(
            text: text,
            provider: .localWhisper,
            modelLabel: label,
            audioDuration: nil,
            estimatedCostUSD: nil,   // local transcription is free
            transcriptionTime: elapsed
        )
    }
}
