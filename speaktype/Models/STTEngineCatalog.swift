import Foundation

/// Config-driven STT engine registry (Part 2 + Part 3 `stt_engines`). Adding an engine = one
/// entry here; adapter wiring is separate. `implemented` marks engines usable *today* through the
/// existing `TranscriptionProvider`s (local Whisper, OpenAI, Groq); the rest are declared with
/// full metadata (languages, streaming, Swedish routing) and marked planned so the UI never
/// offers a non-functional engine.
struct STTEngine: Identifiable, Equatable {
    enum Kind: String { case local, cloud }

    let id: String
    let label: String
    let provider: String          // "local" | "openai" | "groq" | "assemblyai" | ...
    let modelID: String
    let kind: Kind
    let streaming: Bool
    /// ISO language prefixes it handles, or ["*"] for broad multilingual.
    let languages: [String]
    let supportsSwedish: Bool
    /// When Swedish is requested but this engine lacks it, route here instead (Part 2 rule).
    let swedishFallbackEngineID: String?
    /// Usable now via an existing `TranscriptionProvider`. Others are config-ready but not wired.
    let implemented: Bool
    let experimental: Bool
    let note: String
}

enum STTEngineCatalog {
    static let engines: [STTEngine] = [
        // --- Implemented today (existing TranscriptionProvider) ---
        STTEngine(id: "local-whisper", label: "Whisper (on-device)", provider: "local",
                  modelID: "openai_whisper-large-v3_turbo", kind: .local, streaming: false,
                  languages: ["*"], supportsSwedish: true, swedishFallbackEngineID: nil,
                  implemented: true, experimental: false, note: "Local WhisperKit; excellent Swedish."),
        STTEngine(id: "openai-transcribe", label: "OpenAI Transcribe", provider: "openai",
                  modelID: "gpt-4o-transcribe", kind: .cloud, streaming: false,
                  languages: ["*"], supportsSwedish: true, swedishFallbackEngineID: nil,
                  implemented: true, experimental: false, note: "Accuracy baseline, strong Swedish."),
        STTEngine(id: "groq-whisper-turbo", label: "Groq Whisper Large v3 Turbo", provider: "groq",
                  modelID: "whisper-large-v3-turbo", kind: .cloud, streaming: false,
                  languages: ["*"], supportsSwedish: true, swedishFallbackEngineID: nil,
                  implemented: true, experimental: false, note: "Fast + cheap cloud fallback."),

        // --- Declared, adapters planned ---
        STTEngine(id: "parakeet-tdt-0.6b-v3", label: "NVIDIA Parakeet-TDT-0.6B v3", provider: "local",
                  modelID: "nvidia/parakeet-tdt-0.6b-v3", kind: .local, streaming: true,
                  languages: ["en", "sv", "de", "fr", "es"], supportsSwedish: true, swedishFallbackEngineID: nil,
                  implemented: false, experimental: false, note: "Preferred local default: 25 EU langs, ~6.34% WER, no silence hallucinations. Needs NeMo/CoreML runtime."),
        STTEngine(id: "mai-transcribe-1", label: "Microsoft MAI-Transcribe-1", provider: "azure",
                  modelID: "mai-transcribe-1", kind: .cloud, streaming: false,
                  languages: ["*"], supportsSwedish: true, swedishFallbackEngineID: nil,
                  implemented: false, experimental: false, note: "3.8% WER FLEURS, 25 langs (Azure AI Foundry)."),
        STTEngine(id: "assemblyai-universal-3-pro", label: "AssemblyAI Universal-3 Pro", provider: "assemblyai",
                  modelID: "universal-3-pro", kind: .cloud, streaming: true,
                  languages: ["en", "es", "fr", "de", "it", "pt"], supportsSwedish: false,
                  swedishFallbackEngineID: "assemblyai-universal-2",
                  implemented: false, experimental: false, note: "6 langs, NO Swedish → auto-route to Universal-2 for sv."),
        STTEngine(id: "assemblyai-universal-2", label: "AssemblyAI Universal-2", provider: "assemblyai",
                  modelID: "universal-2", kind: .cloud, streaming: true,
                  languages: ["*"], supportsSwedish: true, swedishFallbackEngineID: nil,
                  implemented: false, experimental: false, note: "99 langs incl. Swedish; the sv fallback target."),
        STTEngine(id: "deepgram-nova-3", label: "Deepgram Nova-3 / Flux", provider: "deepgram",
                  modelID: "nova-3", kind: .cloud, streaming: true,
                  languages: ["*"], supportsSwedish: true, swedishFallbackEngineID: nil,
                  implemented: false, experimental: false, note: "Lowest-latency streaming, integrated end-of-turn."),
        STTEngine(id: "openai-gpt-realtime-whisper", label: "OpenAI GPT-Realtime-Whisper", provider: "openai",
                  modelID: "gpt-realtime-whisper", kind: .cloud, streaming: true,
                  languages: ["*"], supportsSwedish: true, swedishFallbackEngineID: nil,
                  implemented: false, experimental: false, note: "$0.017/min streaming."),
        STTEngine(id: "elevenlabs-scribe-v2-realtime", label: "ElevenLabs Scribe v2 Realtime", provider: "elevenlabs",
                  modelID: "scribe-v2-realtime", kind: .cloud, streaming: true,
                  languages: ["*"], supportsSwedish: true, swedishFallbackEngineID: nil,
                  implemented: false, experimental: false, note: "Sub-150ms, 90+ langs."),
        STTEngine(id: "whisper-turbo-live-silero", label: "Whisper Large v3 Turbo (live + Silero VAD)", provider: "local",
                  modelID: "openai_whisper-large-v3_turbo", kind: .local, streaming: true,
                  languages: ["*"], supportsSwedish: true, swedishFallbackEngineID: nil,
                  implemented: false, experimental: false, note: "Pair with aggressive Silero VAD to avoid silence hallucinations."),
        STTEngine(id: "speechmatics-ursa-2", label: "Speechmatics Ursa 2", provider: "speechmatics",
                  modelID: "ursa-2", kind: .cloud, streaming: true,
                  languages: ["*"], supportsSwedish: true, swedishFallbackEngineID: nil,
                  implemented: false, experimental: false, note: "Best code-switching (SV/EN mixing)."),
        STTEngine(id: "voxtral-realtime", label: "Voxtral Realtime", provider: "voxtral",
                  modelID: "voxtral-realtime", kind: .cloud, streaming: true,
                  languages: ["*"], supportsSwedish: true, swedishFallbackEngineID: nil,
                  implemented: false, experimental: true, note: "Emerging — experimental."),
    ]

    static func engine(id: String) -> STTEngine? { engines.first { $0.id == id } }

    static var implementedEngines: [STTEngine] { engines.filter(\.implemented) }

    /// Apply the Swedish auto-routing rule: if `language` is Swedish and the chosen engine lacks
    /// it, return its declared Swedish-capable fallback and log the switch.
    static func resolve(engineID: String, language: String) -> STTEngine? {
        guard let chosen = engine(id: engineID) else { return nil }
        if language.lowercased().hasPrefix("sv"), !chosen.supportsSwedish,
           let fallbackID = chosen.swedishFallbackEngineID, let fallback = engine(id: fallbackID) {
            print("STT: \(chosen.label) lacks Swedish → auto-routing to \(fallback.label).")
            return fallback
        }
        return chosen
    }
}
