import Foundation

// MARK: - User defaults keys (shared by Settings, Onboarding, TranscriptionFinalizer)

enum WritingPolishUserDefaults {
    static let enabledKey = "writingPolishEnabled"
    static let presetKey = "writingPolishPreset"
    static let removeFillersKey = "writingPolishRemoveFillers"
    static let ollamaBaseURLKey = "writingPolishOllamaBaseURL"
    static let ollamaModelKey = "writingPolishOllamaModel"
    static let ollamaTemperatureKey = "writingPolishOllamaTemperature"

    // Cleanup provider selection (Part 1). Default = OpenRouter + latest Gemini flash.
    static let cleanupProviderKey = "cleanupProvider"
    static let cleanupModelKey = "cleanupModelId"
    /// Below this much free RAM, a local (Ollama) cleanup auto-falls back to a configured cloud provider.
    static let cleanupRAMThresholdKey = "cleanupLocalRAMThresholdGB"

    /// Default Ollama HTTP API base. User can point at another host or TLS reverse proxy.
    static let defaultOllamaBaseURL = "http://127.0.0.1:11434"

    /// Default polish model: balanced Qwen 3.5 2B (user can pick another in Settings / onboarding).
    static let defaultOllamaModel = "qwen3.5:2b"

    static let defaultCleanupProvider = CleanupProvider.openRouter.rawValue
    static let defaultCleanupModel = CleanupModel.defaultModelID
    static let defaultCleanupRAMThresholdGB = 6.0

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            enabledKey: true,
            presetKey: WritingPolishPreset.clean.rawValue,
            removeFillersKey: true,
            ollamaBaseURLKey: defaultOllamaBaseURL,
            ollamaModelKey: defaultOllamaModel,
            ollamaTemperatureKey: 0.2,
            cleanupProviderKey: defaultCleanupProvider,
            cleanupModelKey: defaultCleanupModel,
            cleanupRAMThresholdKey: defaultCleanupRAMThresholdGB,
        ])
    }
}

// MARK: - Preset

enum WritingPolishPreset: String, CaseIterable, Identifiable {
    case clean
    case professional
    case casual
    case message
    case bullets

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clean: return "Clean"
        case .professional: return "Professional"
        case .casual: return "Casual"
        case .message: return "Message"
        case .bullets: return "Bullet list"
        }
    }

    var menuDescription: String {
        switch self {
        case .clean:
            return "Fix grammar and punctuation; keep meaning and tone."
        case .professional:
            return "Clear, concise business tone."
        case .casual:
            return "Natural and conversational."
        case .message:
            return "Short lines; good for chat or quick notes."
        case .bullets:
            return "Turn key points into a tight bullet list."
        }
    }

    /// Instruction fragments combined with global guardrails in `WritingPolishService`.
    func styleInstructions(removeFillers: Bool) -> String {
        var lines: [String] = []
        if removeFillers {
            lines.append("Remove filler words (um, uh, like, you know) when they do not carry meaning.")
        }
        switch self {
        case .clean:
            lines.append(
                "Rewrite into clear written prose: fix grammar, spelling, and punctuation. Keep the same meaning and facts. Do not add new information."
            )
        case .professional:
            lines.append(
                "Rewrite in a professional, concise tone suitable for workplace email or documents. Keep the same meaning and facts. Do not add new information."
            )
        case .casual:
            lines.append(
                "Rewrite in a friendly, conversational tone while staying clear. Keep the same meaning and facts. Do not add new information."
            )
        case .message:
            lines.append(
                "Rewrite as a short, scannable message: brief sentences or line breaks where helpful (like chat). Keep the same meaning and facts. Do not add new information."
            )
        case .bullets:
            lines.append(
                "Extract the main points as a bullet list using \"- \" at line starts. Keep ordering logical. Do not invent bullets; only from what was said."
            )
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Configuration

struct WritingPolishConfiguration: Equatable {
    var isEnabled: Bool
    var preset: WritingPolishPreset
    var removeFillers: Bool
    var ollamaBaseURL: String
    var ollamaModel: String
    var ollamaTemperature: Double
    // Defaults so existing initializers (e.g. Settings' config summary) keep compiling.
    var cleanupProvider: CleanupProvider = .openRouter
    var cleanupModelID: String = CleanupModel.defaultModelID
    var cleanupRAMThresholdGB: Double = WritingPolishUserDefaults.defaultCleanupRAMThresholdGB

    static func loadFromUserDefaults(_ defaults: UserDefaults = .standard) -> WritingPolishConfiguration {
        WritingPolishUserDefaults.registerDefaults(in: defaults)
        let enabled = defaults.bool(forKey: WritingPolishUserDefaults.enabledKey)
        let raw = defaults.string(forKey: WritingPolishUserDefaults.presetKey)
            ?? WritingPolishPreset.clean.rawValue
        let preset = WritingPolishPreset(rawValue: raw) ?? .clean
        let removeFillers = defaults.object(forKey: WritingPolishUserDefaults.removeFillersKey) as? Bool
            ?? true
        let base =
            defaults.string(forKey: WritingPolishUserDefaults.ollamaBaseURLKey)
            ?? WritingPolishUserDefaults.defaultOllamaBaseURL
        let model =
            defaults.string(forKey: WritingPolishUserDefaults.ollamaModelKey)
            ?? WritingPolishUserDefaults.defaultOllamaModel
        let temp = defaults.object(forKey: WritingPolishUserDefaults.ollamaTemperatureKey) as? Double
            ?? 0.2
        let cleanupProviderRaw = defaults.string(forKey: WritingPolishUserDefaults.cleanupProviderKey)
            ?? WritingPolishUserDefaults.defaultCleanupProvider
        let cleanupProvider = CleanupProvider(rawValue: cleanupProviderRaw) ?? .openRouter
        let cleanupModel = defaults.string(forKey: WritingPolishUserDefaults.cleanupModelKey)
            ?? WritingPolishUserDefaults.defaultCleanupModel
        let ramThreshold = defaults.object(forKey: WritingPolishUserDefaults.cleanupRAMThresholdKey) as? Double
            ?? WritingPolishUserDefaults.defaultCleanupRAMThresholdGB
        return WritingPolishConfiguration(
            isEnabled: enabled,
            preset: preset,
            removeFillers: removeFillers,
            ollamaBaseURL: base,
            ollamaModel: model,
            ollamaTemperature: temp,
            cleanupProvider: cleanupProvider,
            cleanupModelID: cleanupModel,
            cleanupRAMThresholdGB: ramThreshold
        )
    }
}
