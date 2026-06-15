import XCTest
@testable import PrepOSPipeline
import PrepOSCore
import PrepOSBucketing
import PrepOSIngestion

// In-memory SecretStore fake (the app uses the Keychain; tests must not). Holds the generated
// AES-GCM database key so a reopened store can decrypt.
private final class FakeSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SecretKey: Data] = [:]
    func data(for key: SecretKey) throws -> Data? { lock.lock(); defer { lock.unlock() }; return storage[key] }
    func set(_ data: Data, for key: SecretKey) throws { lock.lock(); defer { lock.unlock() }; storage[key] = data }
    func remove(_ key: SecretKey) throws { lock.lock(); defer { lock.unlock() }; storage[key] = nil }
}

/// Exercises the exact data path the app's PrepOSEngine uses — PrepOSStore facade over a real
/// on-disk EncryptedDatabase + the IngestionCoordinator — including the encryption round-trip
/// across a close/reopen. The only app-only pieces not covered here are the Keychain
/// SecretStore and SwiftUI rendering.
final class PrepOSStoreTests: XCTestCase {
    private var dir: URL!
    private let secrets = FakeSecretStore()

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("prepos-store-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func makeStore() -> PrepOSStore {
        PrepOSStore(cipherURL: dir.appendingPathComponent("db.enc"),
                    workingDirectory: dir, secretStore: secrets)
    }

    func testCapturePersistsAcrossEncryptedReopen() async throws {
        // First session: capture a novel item (cold start → Unsorted + pending triage), persist.
        do {
            let store = makeStore()
            let ingestionStore = try store.open()
            let coordinator = IngestionCoordinator(embedder: DeterministicEmbeddingService(), store: ingestionStore)
            _ = try await coordinator.ingest(.text("a novel topic with no matching bucket"))
            try store.persist()
            XCTAssertEqual(try store.pendingTriage().count, 1)
        }

        // Second session: a fresh facade over the same encrypted file + same key decrypts and
        // sees the persisted state — proving the AES-GCM round-trip and migration survived.
        let reopened = makeStore()
        try reopened.open()
        XCTAssertEqual(try reopened.pendingTriage().count, 1, "captured triage survived encrypted reopen")
        let unsorted = try reopened.items(inBucket: DatabaseIngestionStore.unsortedBucketID)
        XCTAssertEqual(unsorted.count, 1, "captured item survived encrypted reopen")
    }

    func testResolveTriageMovesItemAndClearsInbox() async throws {
        let store = makeStore()
        let ingestionStore = try store.open()
        let coordinator = IngestionCoordinator(embedder: DeterministicEmbeddingService(), store: ingestionStore)
        let result = try await coordinator.ingest(.text("something to sort"))
        let triage = try XCTUnwrap(try store.pendingTriage().first)

        // Resolve: create a destination bucket, re-home the item, clear the triage entry.
        let acme = Bucket(type: .account, name: "Acme")
        try store.upsertBucket(acme)
        try store.moveItem(result.item.id, toBucket: acme.id)
        try store.resolveTriage(triage.id)
        try store.persist()

        XCTAssertTrue(try store.pendingTriage().isEmpty, "inbox cleared")
        XCTAssertEqual(try store.items(inBucket: acme.id).map(\.id), [result.item.id], "item now in Acme")
    }
}
