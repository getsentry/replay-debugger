import Foundation
import Security

/// Manages secure storage of authentication tokens in the macOS Keychain
class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.sentry.replay-debugger"

    private init() {}

    // MARK: - Token Storage Keys

    private enum KeychainKey {
        static let accessToken = "sentry-access-token"
        static let refreshToken = "sentry-refresh-token"
        static let tokenExpiry = "sentry-token-expiry"
    }

    // MARK: - Public Methods

    /// Save OAuth access token to Keychain
    func saveAccessToken(_ token: String) throws {
        try saveToKeychain(value: token, key: KeychainKey.accessToken)
    }

    /// Retrieve OAuth access token from Keychain
    func getAccessToken() -> String? {
        return getFromKeychain(key: KeychainKey.accessToken)
    }

    /// Save OAuth refresh token to Keychain
    func saveRefreshToken(_ token: String) throws {
        try saveToKeychain(value: token, key: KeychainKey.refreshToken)
    }

    /// Retrieve OAuth refresh token from Keychain
    func getRefreshToken() -> String? {
        return getFromKeychain(key: KeychainKey.refreshToken)
    }

    /// Save token expiry timestamp to Keychain
    func saveTokenExpiry(_ expiry: Date) throws {
        let timestamp = String(expiry.timeIntervalSince1970)
        try saveToKeychain(value: timestamp, key: KeychainKey.tokenExpiry)
    }

    /// Retrieve token expiry timestamp from Keychain
    func getTokenExpiry() -> Date? {
        guard let timestampString = getFromKeychain(key: KeychainKey.tokenExpiry),
              let timestamp = TimeInterval(timestampString) else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    /// Check if the access token is expired
    func isTokenExpired() -> Bool {
        guard let expiry = getTokenExpiry() else {
            return true // If we don't know, assume expired
        }
        // Add 60 second buffer to refresh before actual expiry
        return Date().addingTimeInterval(60) >= expiry
    }

    /// Delete all stored tokens (for logout)
    func clearAllTokens() {
        deleteFromKeychain(key: KeychainKey.accessToken)
        deleteFromKeychain(key: KeychainKey.refreshToken)
        deleteFromKeychain(key: KeychainKey.tokenExpiry)
    }

    // MARK: - Private Keychain Operations

    private func saveToKeychain(value: String, key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Try to delete existing item first
        deleteFromKeychain(key: key)

        // Create query for adding new item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private func getFromKeychain(key: String) -> String? {
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

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum KeychainError: Error, LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case notFound

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode token data"
        case .saveFailed(let status):
            return "Failed to save to Keychain (status: \(status))"
        case .notFound:
            return "Token not found in Keychain"
        }
    }
}
