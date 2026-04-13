import Foundation

/// Curated Ollama tags for **writing polish** (instruction-following, rewrite). Sizes are approximate disk after pull (Ollama library).
struct OllamaCatalogEntry: Identifiable, Hashable, Sendable {
    var id: String { ollamaTag }

    /// Exact `ollama pull` name (e.g. `qwen3.5:2b`).
    let ollamaTag: String
    let title: String
    let subtitle: String
    /// Approximate download / on-disk size for user expectations.
    let sizeLabel: String
    let approxSizeGB: Double
    /// Sort order: smallest / fastest first for a frictionless default list.
    let sortOrder: Int
    let badge: String?
    /// Rough minimum **system** RAM (GB) for a decent experience; used for hints only.
    let suggestedMinRAMGB: Int

    static let polishCatalog: [OllamaCatalogEntry] = [
        OllamaCatalogEntry(
            ollamaTag: "qwen3.5:0.8b",
            title: "Qwen 3.5 · 0.8B",
            subtitle: "Tiny and quick — great first try for polish on modest Macs.",
            sizeLabel: "~1.0 GB",
            approxSizeGB: 1.0,
            sortOrder: 0,
            badge: "Lightest",
            suggestedMinRAMGB: 8
        ),
        OllamaCatalogEntry(
            ollamaTag: "qwen3.5:2b",
            title: "Qwen 3.5 · 2B",
            subtitle: "Balanced quality and speed — default we recommend for most users.",
            sizeLabel: "~2.7 GB",
            approxSizeGB: 2.7,
            sortOrder: 1,
            badge: "Recommended",
            suggestedMinRAMGB: 8
        ),
        OllamaCatalogEntry(
            ollamaTag: "nemotron-3-nano:4b",
            title: "NVIDIA Nemotron 3 Nano · 4B",
            subtitle: "Compact NVIDIA-tuned model — strong for short rewrite tasks.",
            sizeLabel: "~2.8 GB",
            approxSizeGB: 2.8,
            sortOrder: 2,
            badge: "NVIDIA",
            suggestedMinRAMGB: 8
        ),
        OllamaCatalogEntry(
            ollamaTag: "ministral-3:3b",
            title: "Mistral Ministral 3 · 3B",
            subtitle: "Efficient Mistral stack; crisp instruction following.",
            sizeLabel: "~3.0 GB",
            approxSizeGB: 3.0,
            sortOrder: 3,
            badge: nil,
            suggestedMinRAMGB: 8
        ),
        OllamaCatalogEntry(
            ollamaTag: "qwen3.5:9b",
            title: "Qwen 3.5 · 9B",
            subtitle: "Heavier but smoother prose when you have headroom.",
            sizeLabel: "~6.6 GB",
            approxSizeGB: 6.6,
            sortOrder: 4,
            badge: "Stronger",
            suggestedMinRAMGB: 16
        ),
        OllamaCatalogEntry(
            ollamaTag: "gemma4:e2b",
            title: "Gemma 4 · E2B",
            subtitle: "Google Gemma 4 edge variant — high quality polish.",
            sizeLabel: "~7.2 GB",
            approxSizeGB: 7.2,
            sortOrder: 5,
            badge: "Gemma 4",
            suggestedMinRAMGB: 16
        ),
        OllamaCatalogEntry(
            ollamaTag: "gemma4:e4b",
            title: "Gemma 4 · E4B",
            subtitle: "Largest Gemma 4 pick here — best polish if RAM allows.",
            sizeLabel: "~9.6 GB",
            approxSizeGB: 9.6,
            sortOrder: 6,
            badge: "Largest",
            suggestedMinRAMGB: 16
        ),
    ]

    static var orderedForPolish: [OllamaCatalogEntry] {
        polishCatalog.sorted { $0.sortOrder < $1.sortOrder }
    }
}
