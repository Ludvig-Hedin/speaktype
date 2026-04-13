import Foundation

/// Talks to a local [Ollama](https://ollama.com) server (`/api/chat`, `/api/pull`) for transcript polish.
/// Prefer tags from `OllamaRecommendedModels.polishCatalog` (e.g. `qwen3.5:2b`); any Ollama tag works for custom installs.
enum OllamaPolishClient {

    enum ClientError: Error, LocalizedError {
        case invalidBaseURL
        case invalidChatURL
        case invalidPullURL
        case emptyResponse
        case httpStatus(Int)
        case pullFailed(String)
        /// Pull stream ended without a terminal `success` status from Ollama.
        case pullStreamIncomplete(model: String)

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL: return "Invalid Ollama base URL."
            case .invalidChatURL: return "Could not build Ollama chat URL."
            case .invalidPullURL: return "Could not build Ollama pull URL."
            case .emptyResponse: return "Ollama returned an empty reply."
            case .httpStatus(let code): return "Ollama HTTP error (\(code))."
            case .pullFailed(let message): return message
            case .pullStreamIncomplete(let model):
                return "Model pull for “\(model)” did not finish successfully (stream ended without success)."
            }
        }
    }

    /// Long timeouts for multi‑GB model pulls.
    private static let pullSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 86400
        return URLSession(configuration: config)
    }()

    private struct ChatRequest: Encodable {
        var model: String
        var messages: [Message]
        var stream: Bool
        var options: Options?

        struct Message: Encodable {
            var role: String
            var content: String
        }

        struct Options: Encodable {
            var temperature: Double
        }
    }

    private struct ChatResponse: Decodable {
        var message: Message

        struct Message: Decodable {
            var role: String?
            var content: String?
        }
    }

    private struct TagsResponse: Decodable {
        var models: [TagModel]?

        struct TagModel: Decodable {
            var name: String?
        }
    }

    /// Normalizes user input: default host, optional `http://`, trim slashes.
    static func normalizeBaseURL(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            t = WritingPolishUserDefaults.defaultOllamaBaseURL
        }
        if !t.lowercased().hasPrefix("http://"), !t.lowercased().hasPrefix("https://") {
            t = "http://" + t
        }
        while t.hasSuffix("/") {
            t.removeLast()
        }
        return t
    }

    static func chatURL(baseURLString: String) -> URL? {
        let base = normalizeBaseURL(baseURLString)
        return URL(string: base + "/api/chat")
    }

    static func tagsURL(baseURLString: String) -> URL? {
        let base = normalizeBaseURL(baseURLString)
        return URL(string: base + "/api/tags")
    }

    static func pullURL(baseURLString: String) -> URL? {
        let base = normalizeBaseURL(baseURLString)
        return URL(string: base + "/api/pull")
    }

    /// Installed model names as reported by Ollama (e.g. `qwen3.5:2b`).
    static func installedModelNames(baseURLString: String) async throws -> [String] {
        guard let url = tagsURL(baseURLString: baseURLString) else {
            throw ClientError.invalidBaseURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.httpStatus(-1) }
        guard (200 ... 299).contains(http.statusCode) else { throw ClientError.httpStatus(http.statusCode) }
        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        return decoded.models?.compactMap(\.name) ?? []
    }

    static func isModelInstalled(tag: String, installedNames: [String]) -> Bool {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        return installedNames.contains { name in
            name == t || name.hasPrefix(t + ":")
        }
    }

    /// `GET /api/tags` — cheap reachability check (does not load a model).
    static func ping(baseURLString: String) async throws {
        _ = try await installedModelNames(baseURLString: baseURLString)
    }

    private struct PullRequestBody: Encodable {
        var model: String
        var stream: Bool
    }

    private struct PullStreamLine: Decodable {
        var status: String?
        var error: String?
        var total: Int64?
        var completed: Int64?
    }

    /// Pull a model with streaming progress.
    static func pullModel(
        baseURLString: String,
        model: String,
        onProgress: (String, Double?) async -> Void
    ) async throws {
        guard let url = pullURL(baseURLString: baseURLString) else {
            throw ClientError.invalidPullURL
        }
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ClientError.pullFailed("Missing model name.") }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PullRequestBody(model: name, stream: true))

        let (bytes, response) = try await pullSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.httpStatus(-1) }
        guard (200 ... 299).contains(http.statusCode) else { throw ClientError.httpStatus(http.statusCode) }

        var sawSuccess = false
        for try await line in bytes.lines {
            guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
            guard let evt = try? JSONDecoder().decode(PullStreamLine.self, from: data) else { continue }
            if let err = evt.error, !err.isEmpty {
                throw ClientError.pullFailed(err)
            }
            let status = evt.status ?? ""
            if status == "success" {
                sawSuccess = true
                await onProgress("Done.", 1.0)
                break
            }
            var fraction: Double?
            if let total = evt.total, total > 0, let completed = evt.completed {
                fraction = min(1.0, max(0, Double(completed) / Double(total)))
            }
            await onProgress(status.isEmpty ? "Downloading…" : status, fraction)
        }
        if !sawSuccess {
            throw ClientError.pullStreamIncomplete(model: name)
        }
    }

    static func polish(
        baseURLString: String,
        model: String,
        temperature: Double,
        systemPrompt: String,
        userTranscript: String
    ) async throws -> String {
        guard let url = chatURL(baseURLString: baseURLString) else {
            throw ClientError.invalidChatURL
        }

        let body = ChatRequest(
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userTranscript),
            ],
            stream: false,
            options: .init(temperature: min(max(temperature, 0), 1.5))
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.httpStatus(-1) }
        guard (200 ... 299).contains(http.statusCode) else { throw ClientError.httpStatus(http.statusCode) }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let text = decoded.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw ClientError.emptyResponse }
        return text
    }
}
