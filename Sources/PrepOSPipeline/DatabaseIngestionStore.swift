import Foundation
import GRDB
import PrepOSCore
import PrepOSBucketing
import PrepOSPersistence
import PrepOSIngestion

/// The GRDB-backed `IngestionStore` (PRD §6, C2). Bridges the capture pipeline to the local
/// database: it builds bucket prototypes from persisted item embeddings, owns the system
/// "Unsorted" bucket, and persists captured items, embeddings, and triage entries.
///
/// `Sendable`: holds only a GRDB `DatabaseWriter` (itself thread-safe) and stateless
/// repositories. The app constructs one of these over its encrypted database queue and hands
/// it to an `IngestionCoordinator`.
public struct DatabaseIngestionStore: IngestionStore {
    /// Stable id of the system "Unsorted" bucket — not-yet-filed items home here until the
    /// user resolves their triage entry. Fixed so it is found, not duplicated, across launches.
    public static let unsortedBucketID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!

    private let database: any DatabaseWriter
    private let buckets: BucketRepository
    private let items: ItemRepository
    private let triage: TriageRepository

    public init(database: any DatabaseWriter) {
        self.database = database
        self.buckets = BucketRepository(database: database)
        self.items = ItemRepository(database: database)
        self.triage = TriageRepository(database: database)
    }

    /// Build a prototype per active bucket from its members' embeddings (centroid + exemplars).
    /// Buckets with no embedded items, and the Unsorted bucket, are excluded — you never file
    /// *into* Unsorted by similarity.
    public func prototypes() async throws -> [UUID: BucketPrototype] {
        var result: [UUID: BucketPrototype] = [:]
        for bucket in try buckets.active() where bucket.id != Self.unsortedBucketID {
            let exemplars = try items.items(inBucket: bucket.id).compactMap { item -> LabeledVector? in
                guard let embedding = try items.embedding(forItem: item.id) else { return nil }
                return LabeledVector(label: item.id, vector: embedding.vector)
            }
            if !exemplars.isEmpty {
                result[bucket.id] = BucketPrototype(exemplars: exemplars)
            }
        }
        return result
    }

    /// Return the Unsorted bucket id, creating the bucket on first use.
    public func unsortedBucketId() async throws -> UUID {
        if try buckets.fetch(id: Self.unsortedBucketID) == nil {
            try buckets.upsert(Bucket(id: Self.unsortedBucketID, type: .topic, name: "Unsorted"))
        }
        return Self.unsortedBucketID
    }

    /// Persist a captured item and its embedding in one place.
    public func persist(item: Item, embedding: [Double]) async throws {
        try items.upsert(item)
        try items.setEmbedding(ItemEmbedding(itemId: item.id, vector: embedding))
    }

    /// Queue a triage entry for the Needs-Sorting inbox.
    public func enqueue(_ triageItem: TriageItem) async throws {
        try triage.upsert(triageItem)
    }
}
