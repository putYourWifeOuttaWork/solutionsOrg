import Foundation
import GRDB
import PrepOSCore
import PrepOSPersistence
import PrepOSIngestion

/// App-facing facade over the encrypted local database (PRD §6, C8). Wraps `EncryptedDatabase`
/// and the GRDB repositories behind a small, GRDB-free surface of `PrepOSCore` types, so the
/// app (the composition root) wires the pipeline without importing GRDB. It also vends the
/// `DatabaseIngestionStore` the `IngestionCoordinator` runs on.
///
/// Not thread-safe by itself; the app drives it from the main actor and calls `persist()` to
/// re-encrypt after mutations.
public final class PrepOSStore: @unchecked Sendable {
    private let encrypted: EncryptedDatabase
    private var writer: (any DatabaseWriter)?

    public init(cipherURL: URL, workingDirectory: URL, secretStore: any SecretStore) {
        self.encrypted = EncryptedDatabase(cipherURL: cipherURL,
                                           workingDirectory: workingDirectory,
                                           secretStore: secretStore)
    }

    /// Open (decrypt + migrate) the database. Returns the ingestion store for the coordinator.
    @discardableResult
    public func open() throws -> DatabaseIngestionStore {
        let queue = try encrypted.open()
        self.writer = queue
        return DatabaseIngestionStore(database: queue)
    }

    /// Re-encrypt the working database back to the ciphertext at rest.
    public func persist() throws { try encrypted.persist() }

    private func db() throws -> any DatabaseWriter {
        guard let writer else { throw PersistenceError.io("PrepOSStore.open() not called") }
        return writer
    }

    // MARK: Core-typed queries (no GRDB types leak out)

    public func allBuckets() throws -> [Bucket] { try BucketRepository(database: db()).all() }
    public func bucket(id: UUID) throws -> Bucket? { try BucketRepository(database: db()).fetch(id: id) }
    public func upsertBucket(_ bucket: Bucket) throws { try BucketRepository(database: db()).upsert(bucket) }
    public func items(inBucket id: UUID) throws -> [Item] { try ItemRepository(database: db()).items(inBucket: id) }
    public func pendingTriage() throws -> [TriageItem] { try TriageRepository(database: db()).pending() }

    /// Re-home an item to a different bucket (the core of resolving a triage entry).
    public func moveItem(_ itemId: UUID, toBucket bucketId: UUID) throws {
        let repo = ItemRepository(database: try db())
        guard var item = try repo.fetch(id: itemId) else { return }
        item.homeBucketId = bucketId
        try repo.upsert(item)
    }

    /// Mark a triage entry resolved so it leaves the Needs-Sorting inbox.
    public func resolveTriage(_ triageId: UUID) throws {
        let repo = TriageRepository(database: try db())
        guard var triage = try repo.fetch(id: triageId) else { return }
        triage.status = .resolved
        try repo.upsert(triage)
    }
}
