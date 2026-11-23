import Foundation

/// A selectable LLM cleanup model. `id` is the provider model slug sent on the wire.
///
/// Catalog refreshed 2026-11-23 from a benchmark on real SpeakType dictations (Swedish, English
/// and mixed; commands and questions addressed to an AI). Every model listed here returned the
/// cleaned text in all 17 cases with the tagged prompt, never answered or translated. Rejected:
/// Gemini 3.1 Flash Lite (answered "Paris"), Mistral Small (translated Swedish), Qwen 3.7 Flash
/// and Tencent HY4 (no no-train endpoint), the `~google/gemini-flash-latest` alias (2–5 s, 30×
/// the price).
///
/// `ModelValidationService` still checks the live `/models` list on startup and disables slugs
/// that stop resolving.
struct CleanupModel: Identifiable, Equatable, Hashable {
    let id: String            // provider model_id
    let provider: CleanupProvider
    let label: String
    let note: String
    /// Some endpoints refuse `reasoning.enabled = false`; those get the lowest effort instead.
    var reasoningRequired: Bool = false

    var displayName: String { label }

    /// Owner decision 2026-11-23: Claude Haiku 5.5 is the default (best on mixed Swedish and
    /// English). With the tagged prompt it passed every case at ~0.8 s median.
    static let defaultModelID = "anthropic/claude-haiku-5.5"

    /// Bumped whenever retired slugs should move users to the new default once.
    static let catalogVersion = 3

    /// Ordered catalog. Picker shows it in this order.
    static let catalog: [CleanupModel] = [
        CleanupModel(id: defaultModelID, provider: .openRouter,
                     label: "Claude Haiku 5.5", note: "Recommended for Swedish and English"),
        CleanupModel(id: "deepseek/deepseek-v4.1-flash-1017", provider: .openRouter,
                     label: "DeepSeek V4.1 Flash", note: "Cheapest, keeps your wording"),
        CleanupModel(id: "openai/gpt-6-luna", provider: .openRouter,
                     label: "GPT-6 Luna", note: "Smoother prose, rewrites a little more"),
        CleanupModel(id: "minimax/minimax-m3.1-flash", provider: .openRouter,
                     label: "MiniMax M3.1 Flash", note: "Fast", reasoningRequired: true),
        CleanupModel(id: "google/gemini-3.5-flash-lite", provider: .openRouter,
                     label: "Gemini 3.5 Flash Lite", note: "Most literal", reasoningRequired: true),
    ]

    static func model(id: String) -> CleanupModel? {
        catalog.first { $0.id == id }
    }

    static var defaultModel: CleanupModel {
        model(id: defaultModelID) ?? catalog[0]
    }

    /// First catalog entry that resolved against the live list — the fallback when the
    /// configured/default model is missing (per the Part 1 fallback rule).
    static func firstResolved(_ resolved: Set<String>) -> CleanupModel? {
        catalog.first { resolved.contains($0.id) }
    }

    /// One-time move off retired slugs (e.g. `openai/gpt-5.6-luna`, the never-resolving
    /// `google/gemini-flash-latest`). A user who picks a current model again keeps it.
    static func migrateRetiredSelection(_ defaults: UserDefaults = .standard) {
        let versionKey = "cleanupCatalogVersion"
        guard defaults.integer(forKey: versionKey) < catalogVersion else { return }
        defaults.set(catalogVersion, forKey: versionKey)
        let key = WritingPolishUserDefaults.cleanupModelKey
        // DeepSeek was briefly the default in an unreleased build that ran on the owner's Mac;
        // move that one install to the chosen default too.
        if let current = defaults.string(forKey: key),
            model(id: current) == nil || current == "deepseek/deepseek-v4.1-flash-1017"
        {
            defaults.set(defaultModelID, forKey: key)
        }
    }
}
