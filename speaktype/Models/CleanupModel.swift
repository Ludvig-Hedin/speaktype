import Foundation

/// A selectable LLM cleanup model. `id` is the provider model slug sent on the wire.
///
/// These slugs are a STARTING POINT — OpenRouter IDs move monthly. `ModelValidationService`
/// fetches the live `/models` list on startup, marks unresolved slugs, and the picker disables
/// them. The built-in default is `google/gemini-flash-latest`, which auto-tracks Google's
/// current flash so it never goes stale.
struct CleanupModel: Identifiable, Equatable, Hashable {
    let id: String            // provider model_id
    let provider: CleanupProvider
    let label: String
    let note: String

    var displayName: String { label }

    /// Default cleanup model — resolves live; auto-tracks the current Gemini flash.
    static let defaultModelID = "google/gemini-flash-latest"

    /// Ordered catalog. First the safe "latest" aliases, then the user's requested slugs
    /// (some may not resolve today — the validator will flag/disable those).
    static let catalog: [CleanupModel] = [
        CleanupModel(id: "google/gemini-flash-latest", provider: .openRouter,
                     label: "Gemini Flash (latest) — default", note: "Best Swedish + latency balance"),
        CleanupModel(id: "google/gemini-3.5-flash", provider: .openRouter,
                     label: "Gemini 3.5 Flash", note: "Pinned Gemini flash"),
        CleanupModel(id: "qwen/qwen3.6-flash", provider: .openRouter,
                     label: "Qwen 3.6 Flash", note: "Fast, flash tier"),
        CleanupModel(id: "minimax/minimax-m3", provider: .openRouter,
                     label: "MiniMax M3", note: ""),
        CleanupModel(id: "deepseek/deepseek-v4-flash", provider: .openRouter,
                     label: "DeepSeek V4 Flash", note: "English-strong, weaker Swedish"),
        CleanupModel(id: "anthropic/claude-haiku-latest", provider: .openRouter,
                     label: "Claude Haiku (latest)", note: "Best instruction-following"),
        CleanupModel(id: "google/gemini-3.1-flash-lite", provider: .openRouter,
                     label: "Gemini 3.1 Flash Lite", note: "Cheapest Gemini"),
        CleanupModel(id: "openai/gpt-5.6-luna", provider: .openRouter,
                     label: "GPT-5.6 Luna", note: ""),
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
}
