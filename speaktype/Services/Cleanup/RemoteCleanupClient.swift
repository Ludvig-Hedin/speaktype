import Foundation

/// OpenAI-compatible `/chat/completions` client for the LLM cleanup step. Handles OpenRouter
/// (default) and OpenAI by swapping base URL + key + headers.
///
/// Security: the key is read at call time (env var → Keychain) and used only for the
/// `Authorization` header — never logged, stored, or returned.
enum RemoteCleanupClient {

    /// VERBATIM per spec — stops the model from ANSWERING the dictated content instead of cleaning it.
    static let systemPrompt = """
        You are a transcription cleanup engine. You receive raw speech-to-text output \
        that may be in English or Swedish or a mix of both. Return ONLY the cleaned \
        text. Do not answer questions, do not add commentary, do not translate. \
        Preserve the speaker's original language and meaning exactly. Fix punctuation, \
        capitalization, filler words (um, äh, liksom), false starts, and obvious \
        transcription errors. Do not add or remove content. Output nothing but the \
        corrected text.
        """

    enum CleanupError: LocalizedError {
        case missingKey
        case badURL
        case unauthorized
        case rateLimited
        case httpStatus(Int)
        case emptyResponse
        case network(String)

        var errorDescription: String? {
            switch self {
            case .missingKey: return "No API key set for the cleanup provider."
            case .badURL: return "Invalid cleanup endpoint."
            case .unauthorized: return "Invalid or expired cleanup API key."
            case .rateLimited: return "Cleanup provider rate limit reached."
            case .httpStatus(let c): return "Cleanup service error (HTTP \(c))."
            case .emptyResponse: return "Cleanup provider returned no text."
            case .network(let m): return "Network error: \(m)"
            }
        }
    }

    static func cleanup(provider: CleanupProvider, modelID: String, transcript: String) async throws -> String {
        guard let url = provider.chatCompletionsURL else { throw CleanupError.badURL }
        guard let key = RemoteAPIKeyStore.read(account: provider.keychainAccount, envVar: provider.envVar) else {
            throw CleanupError.missingKey
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if provider == .openRouter {
            // Headers OpenRouter asks integrators to send.
            request.setValue("https://speaktype.app", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("SpeakType", forHTTPHeaderField: "X-Title")
        }

        var body: [String: Any] = [
            "model": modelID,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": transcript],
            ],
        ]
        if provider == .openRouter {
            // Per-request no-train / privacy routing — dictation isn't used for training.
            body["provider"] = ["data_collection": "deny"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CleanupError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw CleanupError.emptyResponse }
        switch http.statusCode {
        case 200...299: break
        case 401, 403: throw CleanupError.unauthorized
        case 429: throw CleanupError.rateLimited
        default: throw CleanupError.httpStatus(http.statusCode)
        }

        guard let text = parseContent(from: data),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CleanupError.emptyResponse
        }
        return text
    }

    private static func parseContent(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return nil
        }
        return content
    }
}
