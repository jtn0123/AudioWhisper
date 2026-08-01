import Foundation
import Security
import os.log

internal enum KeychainError: Error, LocalizedError {
    case invalidData
    case updateFailed(OSStatus)
    case addFailed(OSStatus)
    case deleteFailed(OSStatus)
    case itemNotFound
    case unexpectedItemFormat
    /// H21: An OSStatus that is neither success nor errSecItemNotFound
    /// (e.g. errSecAuthFailed, errSecInteractionNotAllowed, errSecMissingEntitlement,
    /// errSecDecode). Previously these collapsed into `.itemNotFound`, masking real
    /// auth/keychain failures as "no key configured".
    case osStatusError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Failed to encode keychain data"
        case .updateFailed(let status):
            return "Failed to update keychain item: \(status)"
        case .addFailed(let status):
            return "Failed to add keychain item: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete keychain item: \(status)"
        case .itemNotFound:
            return "Keychain item not found"
        case .unexpectedItemFormat:
            return "Unexpected keychain item format"
        case .osStatusError(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain error \(status): \(message)"
            }
            return "Keychain error \(status)"
        }
    }
}

internal protocol KeychainServiceProtocol {
    func save(_ key: String, service: String, account: String) throws
    func get(service: String, account: String) throws -> String?
    func delete(service: String, account: String) throws

    // Backward compatibility methods that don't throw
    func saveQuietly(_ key: String, service: String, account: String)
    func getQuietly(service: String, account: String) -> String?
    func deleteQuietly(service: String, account: String)
}

internal class KeychainService: KeychainServiceProtocol {
    static var shared: KeychainServiceProtocol = KeychainService()

    private init() {}

    func save(_ key: String, service: String, account: String) throws {
        if key.isEmpty {
            try delete(service: service, account: account)
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)

        guard let keyData = key.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        if status == errSecSuccess {
            let attributes: [String: Any] = [
                kSecValueData as String: keyData
            ]

            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if updateStatus != errSecSuccess {
                throw KeychainError.updateFailed(updateStatus)
            }
        } else {
            let attributes: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: keyData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
            ]

            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw KeychainError.addFailed(addStatus)
            }
        }
    }

    func get(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess {
            guard let data = dataTypeRef as? Data else {
                throw KeychainError.unexpectedItemFormat
            }
            guard let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            // Validate the retrieved key has reasonable characteristics
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                Logger.keychain.warning("Retrieved empty API key for \(account, privacy: .public)")
                return nil
            }
            // Generic secret-length sanity check. The app no longer stores cloud
            // API keys (A4), but this is still a useful corruption signal for any
            // secret. Log a warning for suspiciously short values, never reject.
            if trimmed.count < 20 {
                Logger.keychain.warning("Retrieved unusually short API key (\(trimmed.count) chars) for \(account, privacy: .public)")
            }
            // Warn about excessively long keys that might indicate corrupted data
            if trimmed.count > 500 {
                Logger.keychain.warning("Retrieved unusually long API key (\(trimmed.count) chars) for \(account, privacy: .public)")
            }
            return trimmed
        } else if status == errSecItemNotFound {
            return nil
        } else {
            // H21: Do not silently collapse non-success/non-not-found OSStatus into
            // .itemNotFound. Surface the real status so auth failures, missing
            // entitlements, locked-keychain, etc. can be diagnosed.
            let message = (SecCopyErrorMessageString(status, nil) as String?) ?? "unknown"
            Logger.keychain.error("SecItemCopyMatching failed for \(account, privacy: .public): status=\(status) (\(message, privacy: .public))")
            throw KeychainError.osStatusError(status)
        }
    }

    func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Backward Compatibility Methods

    func saveQuietly(_ key: String, service: String, account: String) {
        do {
            try save(key, service: service, account: account)
        } catch {
            Logger.keychain.error("Keychain operation failed: \(error.localizedDescription)")
        }
    }

    func getQuietly(service: String, account: String) -> String? {
        do {
            return try get(service: service, account: account)
        } catch KeychainError.osStatusError(let status) {
            // H21: distinguish "real" keychain errors from a missing item.
            // Previously these were silently swallowed as "no key", causing
            // confusing UI states ("Configure API key" while the key actually exists
            // but the keychain is locked / auth failed).
            Logger.keychain.warning("getQuietly: keychain returned status \(status) for \(account, privacy: .public) — treating as missing, but underlying access likely failed")
            return nil
        } catch {
            Logger.keychain.error("Keychain operation failed: \(error.localizedDescription)")
            return nil
        }
    }

    func deleteQuietly(service: String, account: String) {
        do {
            try delete(service: service, account: account)
        } catch {
            Logger.keychain.error("Keychain operation failed: \(error.localizedDescription)")
        }
    }
}
