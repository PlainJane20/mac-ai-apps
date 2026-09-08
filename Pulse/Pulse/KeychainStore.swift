//
//  KeychainStore.swift
//  Pulse
//
//  Minimal wrapper around the macOS Keychain for storing small secrets —
//  this is the "right" place for credentials in a shipped app, as opposed
//  to a .env file (fine for a throwaway script, wrong for anything real).
//  Values are scoped by a service name + account name pair, same shape as
//  the underlying Security framework APIs.
//

import Foundation
import Security

struct KeychainStore {
    static func save(service: String, account: String, value: String) {
        let data = Data(value.utf8)
        // Remove any existing item first — SecItemAdd fails on a duplicate
        // rather than overwriting it.
        delete(service: service, account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Available after the user unlocks their Mac once post-boot —
            // right balance for a background app that shouldn't need
            // Face ID/Touch ID prompts just to read its own config.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
