import Foundation
import PrepOSCore

/// In-memory `SecretStore` fake for tests — never touches the Keychain. Thread-safe so it
/// can back the `Sendable` `EncryptedDatabase`. Mirrors the real Keychain semantics: `set`
/// replaces, `data(for:)` returns `nil` when absent, `remove` is idempotent.
final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SecretKey: Data] = [:]

    func data(for key: SecretKey) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    func set(_ data: Data, for key: SecretKey) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
    }

    func remove(_ key: SecretKey) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = nil
    }

    /// Test introspection: how many secrets are stored (used to assert first-use generation).
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return storage.count
    }
}
