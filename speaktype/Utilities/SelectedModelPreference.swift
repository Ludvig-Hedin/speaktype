import Foundation

/// Keeps `UserDefaults` `selectedModelVariant` aligned with what is actually on disk and a RAM-aware default.
/// **Why:** Mini recorder and settings used `""` while the dashboard used a different default, so the hotkey flow showed "No model selected" even when models were downloaded.
enum SelectedModelPreference {
    static let storageKey = "selectedModelVariant"

    static func recommendedVariant() -> String {
        AIModel.recommendedModel(forDeviceRAMGB: WhisperService.deviceRAMGB).variant
    }

    /// Pure selection logic (testable without touching `UserDefaults`).
    static func resolveSelection(
        current: String,
        downloadedVariants: Set<String>,
        recommended: String,
        orderedVariants: [String],
        isActivelyDownloading: (String) -> Bool
    ) -> String {
        if !current.isEmpty, downloadedVariants.contains(current) {
            return current
        }
        if !current.isEmpty, isActivelyDownloading(current) {
            return current
        }
        if downloadedVariants.contains(recommended) {
            return recommended
        }
        if let pick = orderedVariants.first(where: { downloadedVariants.contains($0) }) {
            return pick
        }
        return recommended
    }

    @MainActor
    static func ensureValidSelection(downloadService: ModelDownloadService) {
        let current = UserDefaults.standard.string(forKey: storageKey) ?? ""
        let downloaded = Set(
            downloadService.downloadProgress.filter { $0.value >= 1.0 }.map(\.key)
        )
        let recommended = recommendedVariant()
        let ordered = AIModel.availableModels.map(\.variant)

        let resolved = resolveSelection(
            current: current,
            downloadedVariants: downloaded,
            recommended: recommended,
            orderedVariants: ordered,
            isActivelyDownloading: { variant in
                downloadService.isDownloading[variant] == true
            }
        )

        if resolved != current {
            UserDefaults.standard.set(resolved, forKey: storageKey)
        }
    }

    /// Warm WhisperKit at launch **only when the Mac has ample free RAM** to keep the model
    /// resident (per `ModelMemoryPolicy`). On low-memory Macs this is a no-op — the model loads
    /// lazily on the first hotkey press instead and is released when idle, keeping idle RAM low.
    static func preloadSelectedModelIfDownloaded() async {
        let variant = await MainActor.run { UserDefaults.standard.string(forKey: storageKey) ?? "" }
        guard !variant.isEmpty else { return }
        let progress: Double = await MainActor.run {
            ModelDownloadService.shared.downloadProgress[variant] ?? 0
        }
        guard progress >= 1.0 else { return }

        guard ModelMemoryPolicy.shouldKeepResident(variant: variant) else {
            print("🪶 Low free RAM — skipping launch preload; model loads on first dictation.")
            return
        }
        try? await WhisperService.shared.loadModel(variant: variant)
    }
}
