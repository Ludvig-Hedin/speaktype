import AVFoundation
import Foundation
import OSLog

/// Uploads audio to a cloud provider's OpenAI-compatible `/v1/audio/transcriptions` endpoint.
/// Structure mirrors `OllamaPolishClient`: typed errors, bounded timeout, no state held between calls.
///
/// Security: the API key is read from the Keychain at call time and used only for the request's
/// `Authorization` header. It is never stored in a property, logged, or included in any error.
struct RemoteTranscriptionClient: TranscriptionProvider {
    let provider: RemoteProvider
    let model: RemoteTranscriptionModel
    var requiredRetryRoute: DictationRetryRoute?

    var kind: TranscriptionProviderKind { provider.providerKind }

    enum ClientError: LocalizedError {
        case missingAPIKey
        case badURL
        case unauthorized
        case rateLimited
        case httpStatus(Int)
        case settingsChanged
        case emptyResponse
        case network(String, transient: Bool)

        var allowsBackgroundRetry: Bool {
            switch self {
            case .network(_, let transient): return transient
            case .httpStatus(let code): return (500...599).contains(code)
            default: return false
            }
        }

        // Descriptions are deliberately scrubbed — never echo the key, auth header, or raw provider body.
        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "No API key set for this provider."
            case .badURL: return "Invalid provider endpoint."
            case .unauthorized: return "Invalid or expired API key."
            case .rateLimited: return "Provider rate limit reached — try again shortly."
            case .httpStatus(let code): return "Transcription service error (HTTP \(code))."
            case .settingsChanged: return "Transcription settings changed — retry from History."
            case .emptyResponse: return "The provider returned no transcript."
            case .network(let msg, _): return "Network error: \(msg)"
            }
        }
    }

    func isAvailable() async -> Bool {
        RemoteAPIKeyStore.hasKey(for: provider)
    }

    /// Waits before each retry of a transient failure (timeout, 429, 5xx). Two retries max;
    /// 400/401/403 and other client errors fail immediately.
    private static let retryDelays: [Duration] = [.milliseconds(500), .milliseconds(1500)]

    func transcribeDetailed(audioFile: URL, language: String) async throws -> TranscriptionOutcome {
        let account = provider.keychainAccount
        let envVar = provider.envVar
        let apiKey = await Task.detached(priority: .userInitiated) {
            RemoteAPIKeyStore.read(account: account, envVar: envVar)
        }.value
        try Task.checkCancellation()
        guard let key = apiKey else { throw ClientError.missingAPIKey }

        // Upload a compressed copy (~8× smaller, ~3× faster round trip). If the encoder fails,
        // or a model rejects the format with a 4xx, send the original WAV instead.
        let encodingStarted = Date()
        let compressed = audioFile.pathExtension == "m4a" ? nil : await AudioUploadEncoder.compressedCopy(of: audioFile)
        let elapsedEncoding = Date().timeIntervalSince(encodingStarted)
        AppLogger.transcription.notice(
            "stage=upload_audio_encode seconds=\(elapsedEncoding, format: .fixed(precision: 3)) compressed=\(compressed != nil)")
        defer { if let compressed { try? FileManager.default.removeItem(at: compressed) } }

        let start = Date()
        let text: String
        if let compressed {
            do {
                text = try await upload(compressed, key: key, language: language)
            } catch ClientError.httpStatus(let code) where (400...499).contains(code) {
                print("Compressed upload rejected (\(code)); retrying with WAV")
                text = try await upload(audioFile, key: key, language: language)
            }
        } else {
            text = try await upload(audioFile, key: key, language: language)
        }
        let elapsed = Date().timeIntervalSince(start)

        let duration = await Self.audioDuration(url: audioFile)
        return TranscriptionOutcome(
            text: text,
            provider: provider.providerKind,
            modelLabel: model.name,
            audioDuration: duration,
            estimatedCostUSD: duration.flatMap { model.costEstimate(durationSeconds: $0) },
            transcriptionTime: elapsed
        )
    }

    /// One upload with retries on transient failures (timeout, 429, 5xx).
    private func upload(_ file: URL, key: String, language: String) async throws -> String {
        // Reading the file is blocking I/O; keep it off the main actor.
        let audioData = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: file)
        }.value
        let request = try makeRequest(
            key: key,
            audioData: audioData,
            filename: file.lastPathComponent,
            language: language,
            dictionary: UserDefaults.standard.string(forKey: DictationHints.dictionaryKey) ?? ""
        )

        var attempt = 0
        while true {
            do {
                try Task.checkCancellation()
                if let requiredRetryRoute, requiredRetryRoute != DictationRetryRoute.current {
                    throw ClientError.settingsChanged
                }
                let data = try await send(request)
                guard let text = Self.parseText(from: data) else {
                    throw ClientError.emptyResponse
                }
                return text
            } catch let error as RetryableError {
                guard attempt < Self.retryDelays.count else { throw error.finalError }
                try await Task.sleep(for: Self.retryDelays[attempt])
                attempt += 1
            }
        }
    }

    /// A transient failure worth retrying, with the error to surface if retries run out.
    private struct RetryableError: Error {
        let finalError: ClientError
    }

    /// One HTTP attempt. Throws `RetryableError` for timeouts, 429 and 5xx.
    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            let code = (error as? URLError)?.code
            let transientCodes: [URLError.Code] = [
                .notConnectedToInternet, .networkConnectionLost, .timedOut,
                .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
            ]
            let clientError = ClientError.network(
                error.localizedDescription, transient: code.map(transientCodes.contains) ?? false)
            if code == .timedOut || code == .networkConnectionLost {
                throw RetryableError(finalError: clientError)
            }
            throw clientError
        }

        guard let http = response as? HTTPURLResponse else { throw ClientError.emptyResponse }
        switch http.statusCode {
        case 200...299: return data
        case 401, 403: throw ClientError.unauthorized
        case 429: throw RetryableError(finalError: .rateLimited)
        case 500...599: throw RetryableError(finalError: .httpStatus(http.statusCode))
        default: throw ClientError.httpStatus(http.statusCode)
        }
    }

    // MARK: - Helpers

    func makeRequest(key: String, audioData: Data, filename: String, language: String, dictionary: String) throws -> URLRequest {
        guard let url = provider.transcriptionURL else { throw ClientError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        var fields = [("model", model.id), ("response_format", "json")]
        let languages = model.supportsDictationHints ? DictationHints.languages(for: language) : []
        let keywords = model.supportsDictationHints ? DictationHints.keywords(in: dictionary) : []
        if model.supportsDictationHints && provider == .openRouter && (!languages.isEmpty || !keywords.isEmpty) {
            let format = URL(fileURLWithPath: filename).pathExtension.lowercased()
            if ["wav", "mp3", "flac", "m4a", "ogg", "webm", "aac"].contains(format) {
                // OpenRouter forwards native options on its JSON endpoint under the serving provider's slug.
                var options: [String: [String]] = [:]
                if !languages.isEmpty { options["languages"] = languages }
                if !keywords.isEmpty { options["keywords"] = keywords }
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "model": model.id,
                    "input_audio": ["data": audioData.base64EncodedString(), "format": format],
                    "provider": ["options": ["openai": options]],
                ])
                return request
            }
            // Keep the multipart import path for audio extensions the JSON API doesn't list.
            var context: [String] = []
            if language == DictationHints.swedishEnglish {
                context.append("The audio may mix Swedish and English.")
            }
            if !keywords.isEmpty { context.append("Possible terms: \(keywords.joined(separator: ", ")).") }
            if !context.isEmpty { fields.append(("prompt", context.joined(separator: " "))) }
            if let single = DictationHints.singleLanguage(language) { fields.append(("language", single)) }
        } else if model.supportsDictationHints && provider == .openAI {
            fields += languages.map { ("languages[]", $0) }
            fields += keywords.map { ("keywords[]", $0) }
        } else if let single = DictationHints.singleLanguage(language) {
            fields.append(("language", single))
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(boundary: boundary, audioData: audioData, filename: filename, fields: fields)
        return request
    }

    private static func multipartBody(
        boundary: String, audioData: Data, filename: String, fields: [(String, String)]
    ) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        // file part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        for (name, value) in fields { field(name, value) }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private static func parseText(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["text"] as? String
    }

    private static func audioDuration(url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}
