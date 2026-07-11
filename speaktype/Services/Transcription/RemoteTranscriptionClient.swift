import AVFoundation
import Foundation

/// Uploads audio to a cloud provider's OpenAI-compatible `/v1/audio/transcriptions` endpoint.
/// Structure mirrors `OllamaPolishClient`: typed errors, bounded timeout, no state held between calls.
///
/// Security: the API key is read from the Keychain at call time and used only for the request's
/// `Authorization` header. It is never stored in a property, logged, or included in any error.
struct RemoteTranscriptionClient: TranscriptionProvider {
    let provider: RemoteProvider
    let model: RemoteTranscriptionModel

    var kind: TranscriptionProviderKind { provider.providerKind }

    enum ClientError: LocalizedError {
        case missingAPIKey
        case badURL
        case unauthorized
        case rateLimited
        case httpStatus(Int)
        case emptyResponse
        case network(String)

        // Descriptions are deliberately scrubbed — never echo the key, auth header, or raw provider body.
        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "No API key set for this provider."
            case .badURL: return "Invalid provider endpoint."
            case .unauthorized: return "Invalid or expired API key."
            case .rateLimited: return "Provider rate limit reached — try again shortly."
            case .httpStatus(let code): return "Transcription service error (HTTP \(code))."
            case .emptyResponse: return "The provider returned no transcript."
            case .network(let msg): return "Network error: \(msg)"
            }
        }
    }

    func isAvailable() async -> Bool {
        RemoteAPIKeyStore.hasKey(for: provider)
    }

    func transcribeDetailed(audioFile: URL, language: String) async throws -> TranscriptionOutcome {
        guard let key = RemoteAPIKeyStore.read(for: provider) else { throw ClientError.missingAPIKey }
        guard let url = provider.transcriptionURL else { throw ClientError.badURL }

        let audioData = try Data(contentsOf: audioFile)
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            audioData: audioData,
            filename: audioFile.lastPathComponent,
            modelId: model.id,
            language: language
        )

        let start = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClientError.network(error.localizedDescription)
        }
        let elapsed = Date().timeIntervalSince(start)

        guard let http = response as? HTTPURLResponse else { throw ClientError.emptyResponse }
        switch http.statusCode {
        case 200...299: break
        case 401, 403: throw ClientError.unauthorized
        case 429: throw ClientError.rateLimited
        default: throw ClientError.httpStatus(http.statusCode)
        }

        let text = Self.parseText(from: data)
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.emptyResponse
        }

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

    // MARK: - Helpers

    private static func multipartBody(
        boundary: String, audioData: Data, filename: String, modelId: String, language: String
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

        field("model", modelId)
        field("response_format", "json")
        if language != "auto", !language.isEmpty {
            field("language", language)
        }

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
