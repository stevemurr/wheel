import Foundation
import Security

/// A helper class for securely storing and retrieving sensitive data from the macOS Keychain
class KeychainHelper {
    static let shared = KeychainHelper()

    private let service = "com.wheel.browser"

    private init() {}

    /// Save a string value to the Keychain
    /// - Parameters:
    ///   - value: The string value to save
    ///   - key: The key to associate with the value
    /// - Returns: True if the save was successful, false otherwise
    @discardableResult
    func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // First, try to delete any existing item
        delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieve a string value from the Keychain
    /// - Parameter key: The key associated with the value
    /// - Returns: The stored string value, or nil if not found
    func retrieve(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    /// Delete a value from the Keychain
    /// - Parameter key: The key associated with the value to delete
    /// - Returns: True if the deletion was successful, false otherwise
    @discardableResult
    func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Check if a value exists in the Keychain for the given key
    /// - Parameter key: The key to check
    /// - Returns: True if a value exists, false otherwise
    func exists(forKey key: String) -> Bool {
        return retrieve(forKey: key) != nil
    }
}

// MARK: - Keychain Keys
extension KeychainHelper {
    enum Keys {
        static let llmAPIKey = "llm_api_key"
    }
}
