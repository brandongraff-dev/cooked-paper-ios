import Foundation
import Security

/// A minimal Keychain wrapper for one secret: the paper-trading bearer token. No
/// third-party dependency for something this small — `kSecClassGenericPassword` with
/// `kSecAttrAccessibleAfterFirstUnlock` (survives a background relaunch, cleared on
/// device wipe, never synced to iCloud) is the whole of what a bearer token needs.
enum KeychainStore {
    private static let service = "app.cooked.paper.session"

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        var query = baseQuery(for: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        // Overwrite semantics: delete-then-add is simpler and safe here since this
        // store is never read concurrently with a write from another process.
        SecItemDelete(baseQuery(for: key) as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    private static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
