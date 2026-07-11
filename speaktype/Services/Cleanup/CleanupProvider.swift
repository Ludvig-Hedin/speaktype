import Foundation

/// Where the LLM cleanup step runs. Both remote options are OpenAI-compatible
/// `/chat/completions`, so one client handles them by swapping base URL + key + headers.
enum CleanupProvider: String, CaseIterable, Codable, Identifiable {
    case openRouter   // default remote
    case openAI       // secondary remote
    case ollama       // local (existing behavior)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .openAI: return "OpenAI"
        case .ollama: return "Local (Ollama)"
        }
    }

    var isRemote: Bool { self != .ollama }

    /// Base URL including the version path (no trailing slash). `nil` for local.
    var baseURL: String? {
        switch self {
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .openAI: return "https://api.openai.com/v1"
        case .ollama: return nil
        }
    }

    var chatCompletionsURL: URL? {
        guard let baseURL else { return nil }
        return URL(string: baseURL + "/chat/completions")
    }

    var modelsListURL: URL? {
        guard let baseURL else { return nil }
        return URL(string: baseURL + "/models")
    }

    /// Keychain account for the key. OpenAI shares the STT OpenAI key (`openai_api_key`).
    var keychainAccount: String {
        switch self {
        case .openRouter: return "openrouter_api_key"
        case .openAI: return "openai_api_key"
        case .ollama: return ""
        }
    }

    /// Env var checked before the Keychain (matches the Part 3 `key_env` fields).
    var envVar: String? {
        switch self {
        case .openRouter: return "OPENROUTER_API_KEY"
        case .openAI: return "OPENAI_API_KEY"
        case .ollama: return nil
        }
    }

    var apiKeyURL: String? {
        switch self {
        case .openRouter: return "https://openrouter.ai/keys"
        case .openAI: return "https://platform.openai.com/api-keys"
        case .ollama: return nil
        }
    }

    func hasKey() -> Bool {
        guard isRemote else { return true }
        return RemoteAPIKeyStore.hasKey(account: keychainAccount, envVar: envVar)
    }
}
