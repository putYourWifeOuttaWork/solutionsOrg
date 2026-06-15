import Foundation
import CryptoKit
import PrepOSCore

/// Stateless AES-GCM helpers (Constitution §2, PRD C8.1). Separated from `EncryptedDatabase`
/// so the crypto round-trip is unit-testable without any filesystem. The key material flows
/// exclusively through `SecretStore`; it never appears in `seal`'s output beyond the standard
/// AES-GCM box (nonce ‖ ciphertext ‖ tag), and is never logged or written to disk in plaintext.
public enum DatabaseCrypto {

    /// Fetch the database key from `SecretStore` (`SecretKey.databaseKey`), generating and
    /// storing a fresh 256-bit key on first use. The key is persisted **only** via
    /// `SecretStore.set` (Keychain in the app, in-memory fake in tests) — never to a file.
    public static func loadOrCreateKey(_ store: any SecretStore) throws -> SymmetricKey {
        if let existing = try store.data(for: .databaseKey) {
            return SymmetricKey(data: existing)
        }
        let key = SymmetricKey(size: .bits256)
        let bytes = key.withUnsafeBytes { Data($0) }
        try store.set(bytes, for: .databaseKey)
        return key
    }

    /// Seal `plaintext` under `key`, returning the AES-GCM combined box
    /// (nonce ‖ ciphertext ‖ tag).
    public static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw PersistenceError.io("AES-GCM produced no combined box")
        }
        return combined
    }

    /// Inverse of `seal`. Throws `PersistenceError.decryptionFailed` when the box fails
    /// AES-GCM authentication (wrong key or tampering).
    public static func open(_ box: Data, key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: box)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw PersistenceError.decryptionFailed
        }
    }
}
