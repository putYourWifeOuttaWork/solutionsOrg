import Foundation
import Security
import PrepOSCore

/// The macOS Keychain implementation of `SecretStore` (Security Constitution §1). Secrets are
/// stored as generic-password items with device-only accessibility (`...ThisDeviceOnly`) and
/// are never written anywhere else. This is the only place the app talks to the Keychain;
/// package code depends solely on the `SecretStore` protocol.
struct KeychainSecretStore: SecretStore {
    /// Keychain service namespace for all PrepOS secrets.
    private let service = "dev.altify.prepos"

    private func baseQuery(_ key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }

    func data(for key: SecretKey) throws -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError.unexpected(status)
        }
    }

    func set(_ data: Data, for key: SecretKey) throws {
        // Replace any existing item so writes are idempotent.
        SecItemDelete(baseQuery(key) as CFDictionary)

        var attributes = baseQuery(key)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpected(status) }
    }

    func remove(_ key: SecretKey) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpected(status)
        }
    }
}

enum KeychainError: Error, CustomStringConvertible {
    case unexpected(OSStatus)
    var description: String {
        switch self {
        case .unexpected(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
            return "Keychain error: \(message)"
        }
    }
}
