import Foundation

/// Post-processes Whisper output using a **local Ollama** small LLM (`/api/chat`). Falls back to the raw transcript on any error.
enum WritingPolishService {

    static func buildSystemPrompt(configuration: WritingPolishConfiguration) -> String {
        let guardrails = """
            You transform rough speech transcripts into written text.
            Output ONLY the final text. No preamble, no quotes around the whole answer, no explanations.
            Preserve names, numbers, URLs, and technical terms unless obviously misheard.
            Do not answer questions from the transcript—only rewrite what was said as writing.
            If the input is already clean, return it with minimal edits.
            """
        let style = configuration.preset.styleInstructions(removeFillers: configuration.removeFillers)
        return guardrails + "\n\n" + style
    }

    /// `true` when we will attempt a cleanup call (shows “Polishing…” in the UI).
    static func willPolish(configuration: WritingPolishConfiguration) -> Bool {
        guard configuration.isEnabled else { return false }
        let provider = effectiveProvider(configuration)
        if provider.isRemote { return provider.hasKey() }
        return !configuration.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Resolve the cleanup provider, applying the RAM-low fallback: a **local** cleanup switches
    /// to a configured cloud provider when free RAM drops below the threshold.
    static func effectiveProvider(_ configuration: WritingPolishConfiguration) -> CleanupProvider {
        var provider = configuration.cleanupProvider
        if provider == .ollama,
           SystemMemory.availableMemoryGB() < configuration.cleanupRAMThresholdGB {
            if CleanupProvider.openRouter.hasKey() {
                provider = .openRouter
            } else if CleanupProvider.openAI.hasKey() {
                provider = .openAI
            }
        }
        return provider
    }

    /// Static help text for Settings / Onboarding (no network).
    static func configurationSummary(config: WritingPolishConfiguration) -> String {
        let provider = effectiveProvider(config)
        switch provider {
        case .openRouter, .openAI:
            let model = CleanupModel.model(id: config.cleanupModelID)?.label ?? config.cleanupModelID
            if provider.hasKey() {
                return "Cleans up via \(provider.displayName) · \(model), temperature 0."
            }
            return "Add a \(provider.displayName) API key below to enable cloud cleanup."
        case .ollama:
            let base = OllamaPolishClient.normalizeBaseURL(config.ollamaBaseURL)
            let model = config.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if model.isEmpty {
                return "Set an Ollama model name (e.g. llama3.2:3b)."
            }
            return "Uses local Ollama at \(base) with model “\(model)”."
        }
    }

    /// Best-effort cleanup; falls back to `rawTranscript` on failure.
    static func polish(rawTranscript: String, configuration: WritingPolishConfiguration) async -> String {
        let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rawTranscript }
        guard configuration.isEnabled else { return rawTranscript }

        let provider = effectiveProvider(configuration)

        // Remote cleanup (OpenRouter / OpenAI) uses the verbatim cleanup prompt + temp 0.
        if provider.isRemote, provider.hasKey() {
            do {
                let out = try await RemoteCleanupClient.cleanup(
                    provider: provider,
                    modelID: configuration.cleanupModelID,
                    transcript: trimmed
                )
                let clean = sanitizeModelOutput(out).trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { return clean }
            } catch {
                print("WritingPolishService: remote cleanup (\(provider.rawValue)) failed — \(error.localizedDescription); falling back")
                // fall through to local / raw
            }
        }

        // Local Ollama path (existing behavior + presets).
        let model = configuration.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return rawTranscript }
        do {
            let system = buildSystemPrompt(configuration: configuration)
            let polished = try await OllamaPolishClient.polish(
                baseURLString: configuration.ollamaBaseURL,
                model: model,
                temperature: configuration.ollamaTemperature,
                systemPrompt: system,
                userTranscript: trimmed
            )
            let out = sanitizeModelOutput(polished).trimmingCharacters(in: .whitespacesAndNewlines)
            return out.isEmpty ? rawTranscript : out
        } catch {
            print("WritingPolishService: Ollama polish failed — \(error.localizedDescription)")
            return rawTranscript
        }
    }

    // MARK: - Private

    /// Strip accidental code fences or wrapping quotes from model output.
    private static func sanitizeModelOutput(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = String(s.dropFirst(3))
            if let nl = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: nl)...])
            }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.hasSuffix("```") {
                s = String(s.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let quoted =
            (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'"))
        if quoted, s.count >= 2 {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }
}
