import Foundation
import CryptoKit
import GRDB
import PrepOSCore

/// Whole-file AES-GCM (CryptoKit) wrapper around a GRDB database (Constitution §2, PRD C8.1 /
/// C8.4).
///
/// At rest, the database is an AES-GCM ciphertext blob at `cipherURL` — the system of record.
/// On `open()` the blob is decrypted to a plaintext **working file** (perms `0o600`) that GRDB
/// opens; migrations are then run. On `persist()`/`close()` the working file is re-encrypted and
/// atomically replaces the ciphertext; `close()` additionally removes the plaintext working
/// file. The key comes from `SecretStore` (`SecretKey.databaseKey`), generated on first use and
/// never written to disk in plaintext.
///
/// TRADEOFF (documented). A plaintext working file exists on disk while the database is open —
/// the deliberate cost of plain SQLite without SQLCipher in the MVP. It is owner-only
/// (`0o600`), short-lived, lives in a caller-supplied sandbox/FileVault-protected directory,
/// and is removed on `close()`. FileVault is the defense-in-depth backstop. A future swap to
/// SQLCipher (or page-level encryption) would close this window; the public surface here would
/// not change.
///
/// `Sendable` is sound because all mutable state lives behind `stateLock`; the underlying GRDB
/// `DatabaseQueue` serializes its own access.
public final class EncryptedDatabase: @unchecked Sendable {

    private let cipherURL: URL
    private let workingURL: URL
    private let secretStore: any SecretStore

    private let stateLock = NSLock()
    private var queue: DatabaseQueue?

    /// - Parameters:
    ///   - cipherURL: where the encrypted blob lives (system of record).
    ///   - workingDirectory: sandbox-private dir for the transient plaintext working file.
    ///   - secretStore: source of the AES-GCM key (Keychain in app, fake in tests).
    public init(cipherURL: URL, workingDirectory: URL, secretStore: any SecretStore) {
        self.cipherURL = cipherURL
        self.workingURL = workingDirectory.appendingPathComponent("prepos-working.sqlite")
        self.secretStore = secretStore
    }

    /// Decrypt the ciphertext to the working file (or start an empty DB on first run), run
    /// migrations, and return the GRDB `DatabaseQueue` that repositories build on. Idempotent:
    /// a second `open()` returns the already-open queue.
    @discardableResult
    public func open() throws -> DatabaseQueue {
        stateLock.lock(); defer { stateLock.unlock() }
        if let queue { return queue }

        let key = try DatabaseCrypto.loadOrCreateKey(secretStore)

        if FileManager.default.fileExists(atPath: cipherURL.path) {
            let box = try Data(contentsOf: cipherURL)
            let plaintext = try DatabaseCrypto.open(box, key: key)
            try writeWorkingFile(plaintext)
        } else {
            // First run: start from an empty working file.
            try writeWorkingFile(Data())
        }

        let queue = try DatabaseQueue(path: workingURL.path)
        try PrepOSSchema.migrate(queue)
        self.queue = queue
        return queue
    }

    /// Re-encrypt the current working file and atomically replace the ciphertext. `DatabaseQueue`
    /// commits each write synchronously in rollback-journal mode, so the main SQLite file already
    /// reflects every committed write — no WAL checkpoint is needed.
    public func persist() throws {
        stateLock.lock(); defer { stateLock.unlock() }
        try persistLocked()
    }

    /// `persist()`, then close the GRDB queue and remove the plaintext working file.
    public func close() throws {
        stateLock.lock(); defer { stateLock.unlock() }
        try persistLocked()
        queue = nil   // releases GRDB's file handle
        try? FileManager.default.removeItem(at: workingURL)
    }

    /// Encrypted export/backup (PRD C8.4): persist the live database, then write a fresh
    /// AES-GCM blob of the current working file to `url`. Encrypted under the same
    /// `SecretKey.databaseKey` for the MVP; a user-supplied passphrase is a documented later
    /// extension (Constitution §2 — "re-encrypts under a user-controlled key").
    public func exportEncrypted(to url: URL) throws {
        stateLock.lock(); defer { stateLock.unlock() }
        try persistLocked()
        let key = try DatabaseCrypto.loadOrCreateKey(secretStore)
        let plaintext = try Data(contentsOf: workingURL)
        let box = try DatabaseCrypto.seal(plaintext, key: key)
        try box.write(to: url, options: .atomic)
    }

    // MARK: - Private

    /// Caller must hold `stateLock`. Reads the working file, seals it, and atomically replaces
    /// the ciphertext. (`DatabaseQueue` uses rollback-journal mode, so committed writes are
    /// already flushed to the main file.)
    private func persistLocked() throws {
        guard queue != nil else { return }
        let key = try DatabaseCrypto.loadOrCreateKey(secretStore)
        let plaintext = try Data(contentsOf: workingURL)
        let box = try DatabaseCrypto.seal(plaintext, key: key)
        try box.write(to: cipherURL, options: .atomic)
    }

    /// Write `data` to the working file with owner-only (`0o600`) permissions.
    private func writeWorkingFile(_ data: Data) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: workingURL.path) {
            try fm.removeItem(at: workingURL)
        }
        let created = fm.createFile(
            atPath: workingURL.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        )
        guard created else {
            throw PersistenceError.io("could not create working file at \(workingURL.path)")
        }
    }
}
