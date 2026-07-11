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

    @discardableResult
    static func save(_ key: String, for provider: RemoteProvider) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }

        // Replace any existing value.
        delete(for: provider)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: provider.keychainAccount,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func read(for provider: RemoteProvider) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: provider.keychainAccount,
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
    static func delete(for provider: RemoteProvider) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: provider.keychainAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static func hasKey(for provider: RemoteProvider) -> Bool {
        read(for: provider) != nil
    }
}
