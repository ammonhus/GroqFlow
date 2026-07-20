import Foundation
import Security

// Generic-password Keychain wrapper. The Groq API key lives here, never on disk.
public enum KeychainHelper {
    public static func get(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    public static func set(_ value: String, service: String, account: String) -> Bool {
        let data = Data(value.utf8)

        // Delete any existing item first, then add fresh. This avoids
        // SecItemUpdate failing on an item whose access control belongs to a
        // previous code signature (e.g. after re-signing the app), which would
        // otherwise silently drop the write and leave the app keyless.
        delete(service: service, account: account)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    public static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
