import Foundation

/// How the app chooses between on-device and cloud transcription.
enum TranscriptionMode: String, CaseIterable, Identifiable {
    /// Never leaves the device. Default — privacy-safe.
    case localOnly
    /// Prefer whichever suits current resources; fall back to the other.
    case auto
    /// Prefer the cloud; fall back to local if the cloud is unavailable.
    case remoteOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .localOnly: return "On-device only"
        case .auto: return "Automatic"
        case .remoteOnly: return "Cloud only"
        }
    }

    var explanation: String {
        switch self {
        case .localOnly:
            return "Audio never leaves your Mac. Uses the downloaded Whisper model."
        case .auto:
            return "Picks on-device when your Mac has resources to spare, and the cloud when it's busy or low on memory. Falls back automatically."
        case .remoteOnly:
            return "Always uses your chosen cloud provider. Falls back to on-device if the cloud is unreachable."
        }
    }

    /// Whether this mode can ever upload audio (used to gate the consent prompt).
    var canUseRemote: Bool { self != .localOnly }
}

/// UserDefaults-backed selection for transcription mode + remote provider/model. Only the API
/// **key** lives in the Keychain (`RemoteAPIKeyStore`); provider/model/mode are plain defaults,
/// matching how `WritingPolishUserDefaults` stores endpoint + model.
enum TranscriptionModeUserDefaults {
    static let modeKey = "transcriptionMode"
    static let remoteProviderKey = "remoteTranscriptionProvider"
    static let remoteModelKey = "remoteTranscriptionModel"
    static let consentKey = "remoteTranscriptionConsentAccepted"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            modeKey: TranscriptionMode.localOnly.rawValue
        ])
    }

    static var mode: TranscriptionMode {
        get {
            let raw = UserDefaults.standard.string(forKey: modeKey) ?? TranscriptionMode.localOnly.rawValue
            return TranscriptionMode(rawValue: raw) ?? .localOnly
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    static var selectedRemoteProvider: RemoteProvider? {
        guard let raw = UserDefaults.standard.string(forKey: remoteProviderKey) else { return nil }
        return RemoteProvider(rawValue: raw)
    }

    /// The remote model resolved against the selected provider, defaulting to that provider's
    /// first catalog entry when nothing valid is stored.
    static var selectedRemoteModel: RemoteTranscriptionModel? {
        guard let provider = selectedRemoteProvider else { return nil }
        if let id = UserDefaults.standard.string(forKey: remoteModelKey),
           let model = RemoteTranscriptionModel.model(id: id), model.provider == provider {
            return model
        }
        return RemoteTranscriptionModel.defaultModel(for: provider)
    }

    static var hasRemoteConsent: Bool {
        get { UserDefaults.standard.bool(forKey: consentKey) }
        set { UserDefaults.standard.set(newValue, forKey: consentKey) }
    }

    /// True when a provider is chosen, its key is stored, and the user consented to uploading audio.
    static var isRemoteConfigured: Bool {
        guard let provider = selectedRemoteProvider else { return false }
        return RemoteAPIKeyStore.hasKey(for: provider) && hasRemoteConsent
    }
}
