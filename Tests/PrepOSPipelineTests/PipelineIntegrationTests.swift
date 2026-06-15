import XCTest
import GRDB
@testable import PrepOSPipeline
import PrepOSCore
import PrepOSBucketing
import PrepOSPersistence
import PrepOSIngestion

/// End-to-end: an `IngestionCoordinator` over the real GRDB-backed `DatabaseIngestionStore`,
/// against an in-memory database. Proves the capture→parse→embed→decide→persist pipeline works
/// with actual persistence (not a fake).
final class PipelineIntegrationTests: XCTestCase {
    private var queue: DatabaseQueue!
    private let embedder = DeterministicEmbeddingService()
    private var store: DatabaseIngestionStore!
    private var coordinator: IngestionCoordinator!

    override func setUpWithError() throws {
        queue = try DatabaseQueue()                 // in-memory
        try PrepOSSchema.migrate(queue)
        store = DatabaseIngestionStore(database: queue)
        coordinator = IngestionCoordinator(embedder: embedder, store: store)
    }

    override func tearDown() { queue = nil; store = nil; coordinator = nil }

    func testColdStartProposesNewBucketAndPersistsToUnsorted() async throws {
        let result = try await coordinator.ingest(.text("a brand new topic with no bucket yet"))

        guard case .newBucketProposed = result.disposition else {
            return XCTFail("cold start should propose a new bucket, got \(result.disposition)")
        }
        // Item parked in Unsorted, with a pending triage entry.
        XCTAssertEqual(result.item.homeBucketId, DatabaseIngestionStore.unsortedBucketID)
        let inUnsorted = try ItemRepository(database: queue).items(inBucket: DatabaseIngestionStore.unsortedBucketID)
        XCTAssertEqual(inUnsorted.count, 1)
        XCTAssertEqual(try TriageRepository(database: queue).pending().count, 1)
    }

    func testCaptureAutoFilesToMatchingBucket() async throws {
        // Seed an "Acme" bucket with one embedded item.
        let acme = Bucket(type: .account, name: "Acme")
        try BucketRepository(database: queue).upsert(acme)
        let seedText = "Acme renewal — pricing and timeline"
        let seedItem = Item(type: .note, title: "seed", body: seedText,
                            homeBucketId: acme.id, confidence: 1, capturedVia: .paste)
        try ItemRepository(database: queue).upsert(seedItem)
        try ItemRepository(database: queue).setEmbedding(
            ItemEmbedding(itemId: seedItem.id, vector: try await embedder.embed(seedText)))

        // Capturing the same content embeds identically → cosine 1.0 → auto-file to Acme.
        let result = try await coordinator.ingest(.text(seedText))

        guard case let .autoFiled(bucketId, score) = result.disposition else {
            return XCTFail("expected autoFiled, got \(result.disposition)")
        }
        XCTAssertEqual(bucketId, acme.id)
        XCTAssertGreaterThanOrEqual(score, AppConfig.default.tHigh)
        XCTAssertEqual(try ItemRepository(database: queue).items(inBucket: acme.id).count, 2)
        XCTAssertEqual(try TriageRepository(database: queue).pending().count, 0, "auto-file makes no triage")
    }

    func testPrototypesExcludeUnsortedAndEmptyBuckets() async throws {
        _ = try await store.unsortedBucketId()                       // create Unsorted
        try BucketRepository(database: queue).upsert(Bucket(type: .project, name: "Empty"))  // no items

        let acme = Bucket(type: .account, name: "Acme")
        try BucketRepository(database: queue).upsert(acme)
        let item = Item(type: .note, title: "s", body: "acme stuff",
                        homeBucketId: acme.id, confidence: 1, capturedVia: .paste)
        try ItemRepository(database: queue).upsert(item)
        try ItemRepository(database: queue).setEmbedding(
            ItemEmbedding(itemId: item.id, vector: try await embedder.embed("acme stuff")))

        let prototypes = try await store.prototypes()
        XCTAssertEqual(Array(prototypes.keys), [acme.id], "only the non-empty, non-Unsorted bucket")
    }

    func testUnsortedBucketIsCreatedOnceAndReused() async throws {
        let first = try await store.unsortedBucketId()
        let second = try await store.unsortedBucketId()
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, DatabaseIngestionStore.unsortedBucketID)
        // Only one bucket row exists.
        XCTAssertEqual(try BucketRepository(database: queue).all().count, 1)
    }
}
