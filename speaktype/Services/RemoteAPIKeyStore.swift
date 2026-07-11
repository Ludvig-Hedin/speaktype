import Foundation
import Security

/// Secure storage for remote provider API keys, kept **separate** from the license keychain
/// item so it can never disturb licensing. Mirrors the proven generic-password pattern in
/// `KeychainHelper`, but keyed per provider account.
///
/// Security notes:
/// - Keys live ONLY in the Keychain — never UserDefaults, plist, logs, or `TranscriptionOutcome`.
/// - `read` returns `nil` rather than throwing, so callers never accidentally log an error that
///   might echo request context.
enum RemoteAPIKeyStore {
    private static let service = "sh.polar.speaktype.apikeys"

    // MARK: - Account-string core (works for any provider: STT or cleanup)

    @discardableResult
    static func save(_ key: String, account: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }
        delete(account: account)  // replace any existing value
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// Resolve a key. Precedence: process **env var** (dev convenience when launched from a
    /// shell) → **Keychain** (how UI-entered keys are stored). Env-only can't work for a
    /// Finder-launched `.app`, so the Keychain is the real path for end users.
    static func read(account: String, envVar: String? = nil) -> String? {
        if let envVar,
           let v = ProcessInfo.processInfo.environment[envVar]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !v.isEmpty {
            return v
        }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static func hasKey(account: String, envVar: String? = nil) -> Bool {
        read(account: account, envVar: envVar) != nil
    }

    // MARK: - RemoteProvider (STT) convenience

    @discardableResult
    static func save(_ key: String, for provider: RemoteProvider) -> Bool {
        save(key, account: provider.keychainAccount)
    }

    static func read(for provider: RemoteProvider) -> String? {
        read(account: provider.keychainAccount, envVar: provider.envVar)
    }

    @discardableResult
    static func delete(for provider: RemoteProvider) -> Bool {
        delete(account: provider.keychainAccount)
    }

    static func hasKey(for provider: RemoteProvider) -> Bool {
        read(for: provider) != nil
    }
}
