import Foundation

/// Failures from the persistence layer (typed per target, per `docs/architecture.md` §6).
public enum PersistenceError: Error, Sendable, Equatable {
    /// The on-disk ciphertext failed AES-GCM authentication (tampered or wrong key).
    case decryptionFailed
    /// The database key was neither found in nor storable via `SecretStore`.
    case missingDatabaseKey
    /// A working-file / filesystem operation failed.
    case io(String)
}
