import Foundation

/// A cloud transcription provider. Both currently expose an OpenAI-compatible
/// `/v1/audio/transcriptions` endpoint, so one client handles both via a per-provider base URL.
enum RemoteProvider: String, CaseIterable, Codable, Identifiable {
    case openAI
    case groq

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .groq: return "Groq"
        }
    }

    /// Base URL (no trailing slash). Groq's OpenAI-compatible surface lives under `/openai`.
    var baseURLString: String {
        switch self {
        case .openAI: return "https://api.openai.com"
        case .groq: return "https://api.groq.com/openai"
        }
    }

    var transcriptionPath: String { "/v1/audio/transcriptions" }

    var transcriptionURL: URL? { URL(string: baseURLString + transcriptionPath) }

    /// Keychain account name for this provider's API key (see `RemoteAPIKeyStore`).
    var keychainAccount: String {
        switch self {
        case .openAI: return "openai_api_key"
        case .groq: return "groq_api_key"
        }
    }

    var providerKind: TranscriptionProviderKind {
        switch self {
        case .openAI: return .openAI
        case .groq: return .groq
        }
    }

    /// Where the user creates an API key — shown as a help link in settings.
    var apiKeyURL: String {
        switch self {
        case .openAI: return "https://platform.openai.com/api-keys"
        case .groq: return "https://console.groq.com/keys"
        }
    }
}

/// A remote transcription model + its pricing, used for the picker and cost estimation.
///
/// NOTE: prices are **estimates** as of 2026 and change — verify against each provider's
/// pricing page. They are only used to show an approximate running cost in Statistics.
struct RemoteTranscriptionModel: Identifiable, Equatable, Hashable {
    let id: String            // API model id sent to the provider
    let provider: RemoteProvider
    let name: String          // human label
    let note: String          // short descriptor for the picker
    let pricePerMinuteUSD: Double?

    /// Estimated USD cost for a clip of the given length.
    func costEstimate(durationSeconds: TimeInterval) -> Double? {
        guard let price = pricePerMinuteUSD, durationSeconds > 0 else { return nil }
        return (durationSeconds / 60.0) * price
    }

    static let catalog: [RemoteTranscriptionModel] = [
        // OpenAI — https://openai.com/api/pricing
        RemoteTranscriptionModel(
            id: "gpt-4o-mini-transcribe", provider: .openAI,
            name: "GPT-4o mini Transcribe", note: "Fast · cheapest OpenAI",
            pricePerMinuteUSD: 0.003
        ),
        RemoteTranscriptionModel(
            id: "gpt-4o-transcribe", provider: .openAI,
            name: "GPT-4o Transcribe", note: "Highest accuracy",
            pricePerMinuteUSD: 0.006
        ),
        RemoteTranscriptionModel(
            id: "whisper-1", provider: .openAI,
            name: "Whisper v2 (whisper-1)", note: "Classic Whisper",
            pricePerMinuteUSD: 0.006
        ),
        // Groq — https://groq.com/pricing (billed per audio-hour, normalized to per-minute here)
        RemoteTranscriptionModel(
            id: "whisper-large-v3-turbo", provider: .groq,
            name: "Whisper Large v3 Turbo", note: "Very fast · very cheap",
            pricePerMinuteUSD: 0.000667   // ~$0.04 / audio-hour
        ),
        RemoteTranscriptionModel(
            id: "whisper-large-v3", provider: .groq,
            name: "Whisper Large v3", note: "Most accurate Groq",
            pricePerMinuteUSD: 0.00185    // ~$0.111 / audio-hour
        ),
    ]

    static func models(for provider: RemoteProvider) -> [RemoteTranscriptionModel] {
        catalog.filter { $0.provider == provider }
    }

    static func model(id: String) -> RemoteTranscriptionModel? {
        catalog.first { $0.id == id }
    }

    /// First model for a provider — the default when the user picks a provider with no model set.
    static func defaultModel(for provider: RemoteProvider) -> RemoteTranscriptionModel? {
        models(for: provider).first
    }
}
