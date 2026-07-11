import Foundation

/// Which engine produced a transcript. String-backed so it can be persisted in history JSON.
enum TranscriptionProviderKind: String, Codable, CaseIterable {
    case localWhisper
    case openAI
    case groq

    var displayName: String {
        switch self {
        case .localWhisper: return "On-device"
        case .openAI: return "OpenAI"
        case .groq: return "Groq"
        }
    }

    /// Remote providers upload audio off-device — used to gate consent + the recorder hint.
    var isRemote: Bool { self != .localWhisper }
}

/// Result of a transcription, carrying provenance + cost so history/stats can record where a
/// transcript came from and what it cost — without widening every call-site's return type.
struct TranscriptionOutcome {
    let text: String
    let provider: TranscriptionProviderKind
    /// Human label for history (e.g. "Whisper Large v3 Turbo", "gpt-4o-transcribe").
    let modelLabel: String
    /// Billed audio length in seconds, when known (used for cost).
    let audioDuration: TimeInterval?
    /// Estimated USD cost. `nil` for local (free) or when pricing is unknown.
    let estimatedCostUSD: Double?
    /// Wall-clock time the transcription took.
    let transcriptionTime: TimeInterval
}

/// Common abstraction the local Whisper engine and remote API clients both conform to, so the
/// coordinator can pick one at runtime and fall back to another.
protocol TranscriptionProvider {
    var kind: TranscriptionProviderKind { get }
    /// Cheap, no-network readiness check (local model downloaded / remote key present).
    func isAvailable() async -> Bool
    /// Named distinctly from `WhisperService.transcribe(...) -> String` to avoid a
    /// return-type-only overload collision on the same type.
    func transcribeDetailed(audioFile: URL, language: String) async throws -> TranscriptionOutcome
}
