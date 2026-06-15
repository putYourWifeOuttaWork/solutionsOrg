import XCTest
import CryptoKit
import GRDB
import PrepOSCore
@testable import PrepOSPersistence

/// AES-GCM encryption-at-rest (`docs/design-notes/persistence.md` §4 tests 11–17): in-memory
/// crypto round-trips, key lifecycle through the fake `SecretStore`, the encrypted-file
/// open/close/reopen cycle, encrypted export, and the Constitution boundary asserts.
final class EncryptionTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("preposenc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Crypto round-trip (tests 11, 12)

    func testSealOpenRoundTripIdenticalBytes() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("the quick brown fox".utf8)
        let box = try DatabaseCrypto.seal(plaintext, key: key)
        XCTAssertEqual(try DatabaseCrypto.open(box, key: key), plaintext)
    }

    func testOpenWithWrongKeyThrowsDecryptionFailed() throws {
        let key = SymmetricKey(size: .bits256)
        let other = SymmetricKey(size: .bits256)
        let box = try DatabaseCrypto.seal(Data("secret".utf8), key: key)
        XCTAssertThrowsError(try DatabaseCrypto.open(box, key: other)) { error in
            XCTAssertEqual(error as? PrepOSPersistence.PersistenceError, .decryptionFailed)
        }
    }

    func testOpenWithTamperedBoxThrows() throws {
        let key = SymmetricKey(size: .bits256)
        var box = try DatabaseCrypto.seal(Data("secret".utf8), key: key)
        box[box.count - 1] ^= 0xFF   // flip a tag byte
        XCTAssertThrowsError(try DatabaseCrypto.open(box, key: key)) { error in
            XCTAssertEqual(error as? PrepOSPersistence.PersistenceError, .decryptionFailed)
        }
    }

    // MARK: - Key lifecycle (test 13)

    func testLoadOrCreateKeyGeneratesOnceThenReturnsSame() throws {
        let store = InMemorySecretStore()
        XCTAssertEqual(store.count, 0)
        let first = try DatabaseCrypto.loadOrCreateKey(store)
        XCTAssertEqual(store.count, 1)
        let second = try DatabaseCrypto.loadOrCreateKey(store)
        XCTAssertEqual(
            first.withUnsafeBytes { Data($0) },
            second.withUnsafeBytes { Data($0) }
        )
        XCTAssertEqual(store.count, 1)   // no second generation
    }

    // MARK: - Encrypted file round-trip + boundary (tests 14, 16, 17)

    func testEncryptedDatabaseOpenWriteCloseReopen() throws {
        let cipherURL = tempDir.appendingPathComponent("db.aesgcm")
        let store = InMemorySecretStore()
        let secretName = "Wonka Renewal Megadeal"

        do {
            let edb = EncryptedDatabase(cipherURL: cipherURL, workingDirectory: tempDir,
                                        secretStore: store)
            let queue = try edb.open()
            let repo = BucketRepository(database: queue)
            try repo.upsert(Bucket(type: .opportunity, name: secretName))
            try edb.close()
        }

        // Ciphertext is on disk; the plaintext working file is gone.
        XCTAssertTrue(FileManager.default.fileExists(atPath: cipherURL.path))
        let workingFile = tempDir.appendingPathComponent("prepos-working.sqlite")
        XCTAssertFalse(FileManager.default.fileExists(atPath: workingFile.path))

        // Ciphertext is not a readable SQLite file and does not leak plaintext field values.
        let onDisk = try Data(contentsOf: cipherURL)
        XCTAssertFalse(onDisk.starts(with: Data("SQLite format 3\u{0}".utf8)))
        XCTAssertNil(rangeOf(Data(secretName.utf8), in: onDisk),
                     "plaintext bucket name leaked into ciphertext")

        // Reopen and read the row back.
        let edb2 = EncryptedDatabase(cipherURL: cipherURL, workingDirectory: tempDir,
                                     secretStore: store)
        let queue2 = try edb2.open()
        let names = try BucketRepository(database: queue2).all().map(\.name)
        XCTAssertEqual(names, [secretName])
        try edb2.close()
    }

    func testKeyBytesNeverAppearInCiphertext() throws {
        // Boundary (test 16): the raw key Data is not a subrange of seal's output.
        let store = InMemorySecretStore()
        let key = try DatabaseCrypto.loadOrCreateKey(store)
        let keyData = key.withUnsafeBytes { Data($0) }
        let box = try DatabaseCrypto.seal(Data("plaintext payload".utf8), key: key)
        XCTAssertNil(rangeOf(keyData, in: box))
    }

    // MARK: - Encrypted export (test 15)

    func testExportEncryptedDecryptsToValidDatabase() throws {
        let cipherURL = tempDir.appendingPathComponent("db.aesgcm")
        let exportURL = tempDir.appendingPathComponent("backup.aesgcm")
        let store = InMemorySecretStore()

        let edb = EncryptedDatabase(cipherURL: cipherURL, workingDirectory: tempDir,
                                    secretStore: store)
        let queue = try edb.open()
        let bucket = Bucket(type: .account, name: "Export Co")
        try BucketRepository(database: queue).upsert(bucket)
        try edb.exportEncrypted(to: exportURL)
        try edb.close()

        // Decrypt the export with the stored key, write the plaintext SQLite to disk, open it.
        let key = try DatabaseCrypto.loadOrCreateKey(store)
        let plaintext = try DatabaseCrypto.open(Data(contentsOf: exportURL), key: key)
        let restored = tempDir.appendingPathComponent("restored.sqlite")
        try plaintext.write(to: restored)
        let restoredQueue = try DatabaseQueue(path: restored.path)
        let names = try BucketRepository(database: restoredQueue).all().map(\.name)
        XCTAssertEqual(names, ["Export Co"])
    }

    /// Brute-force subrange search over `Data` (small test inputs).
    private func rangeOf(_ needle: Data, in haystack: Data) -> Range<Int>? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        let n = Array(needle), h = Array(haystack)
        for start in 0...(h.count - n.count) where Array(h[start..<start + n.count]) == n {
            return start..<(start + n.count)
        }
        return nil
    }
}
