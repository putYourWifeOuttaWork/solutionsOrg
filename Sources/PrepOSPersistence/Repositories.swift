import Foundation
import GRDB
import PrepOSCore

// Repositories: CRUD + the key queries (items in a bucket; pending triage). Each wraps a
// GRDB `DatabaseWriter` (a `DatabaseQueue`/`DatabasePool`), which serializes writes, so the
// repos are trivially `Sendable`. `upsert` uses GRDB's `save`, which inserts or replaces by
// primary key — re-`upsert`ing an existing id updates in place rather than duplicating.

/// CRUD + key queries for buckets (PRD §6.1). Writes serialize through the shared writer.
public struct BucketRepository: Sendable {
    private let database: any DatabaseWriter
    public init(database: any DatabaseWriter) { self.database = database }

    /// Insert `bucket`, or replace the row with the same `id`.
    public func upsert(_ bucket: Bucket) throws {
        try database.write { try bucket.save($0) }
    }

    /// The bucket with `id`, or `nil` if none.
    public func fetch(id: UUID) throws -> Bucket? {
        try database.read { try Bucket.fetchOne($0, key: id.uuidString) }
    }

    /// Every bucket.
    public func all() throws -> [Bucket] {
        try database.read { try Bucket.fetchAll($0) }
    }

    /// Buckets whose `status == .active` (PRD §6.1 lifecycle).
    public func active() throws -> [Bucket] {
        try database.read { db in
            try Bucket
                .filter(Column("status") == BucketStatus.active.rawValue)
                .fetchAll(db)
        }
    }

    /// Remove the bucket with `id` (cascades to its items, links, and embeddings).
    public func delete(id: UUID) throws {
        _ = try database.write { try Bucket.deleteOne($0, key: id.uuidString) }
    }
}

/// CRUD + "items in a bucket" (PRD C7.1 retrieval) and embedding co-storage (PRD §6.2).
public struct ItemRepository: Sendable {
    private let database: any DatabaseWriter
    public init(database: any DatabaseWriter) { self.database = database }

    /// Insert `item`, or replace the row with the same `id`.
    public func upsert(_ item: Item) throws {
        try database.write { try item.save($0) }
    }

    /// The item with `id`, or `nil` if none.
    public func fetch(id: UUID) throws -> Item? {
        try database.read { try Item.fetchOne($0, key: id.uuidString) }
    }

    /// Items whose `homeBucketId == bucketId`, newest first (PRD C7.1).
    public func items(inBucket bucketId: UUID) throws -> [Item] {
        try database.read { db in
            try Item
                .filter(Column("homeBucketId") == bucketId.uuidString)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    /// Remove the item with `id` (cascades to its embedding and triage rows).
    public func delete(id: UUID) throws {
        _ = try database.write { try Item.deleteOne($0, key: id.uuidString) }
    }

    /// Store (or replace) the embedding for its item.
    public func setEmbedding(_ embedding: ItemEmbedding) throws {
        try database.write { try embedding.save($0) }
    }

    /// The stored embedding for `itemId`, or `nil` if none.
    public func embedding(forItem itemId: UUID) throws -> ItemEmbedding? {
        try database.read { try ItemEmbedding.fetchOne($0, key: itemId.uuidString) }
    }
}

/// CRUD + the "pending triage" query backing the Needs-Sorting inbox (PRD §6.7, C2.4).
public struct TriageRepository: Sendable {
    private let database: any DatabaseWriter
    public init(database: any DatabaseWriter) { self.database = database }

    public func upsert(_ item: TriageItem) throws {
        try database.write { try item.save($0) }
    }

    public func fetch(id: UUID) throws -> TriageItem? {
        try database.read { try TriageItem.fetchOne($0, key: id.uuidString) }
    }

    /// All triage items with `status == .pending`.
    public func pending() throws -> [TriageItem] {
        try database.read { db in
            try TriageItem
                .filter(Column("status") == TriageStatus.pending.rawValue)
                .fetchAll(db)
        }
    }

    public func delete(id: UUID) throws {
        _ = try database.write { try TriageItem.deleteOne($0, key: id.uuidString) }
    }
}

/// CRUD for bucket-relatedness edges (PRD §6.3).
public struct BucketLinkRepository: Sendable {
    private let database: any DatabaseWriter
    public init(database: any DatabaseWriter) { self.database = database }

    public func upsert(_ link: BucketLink) throws {
        try database.write { try link.save($0) }
    }
    public func fetch(id: UUID) throws -> BucketLink? {
        try database.read { try BucketLink.fetchOne($0, key: id.uuidString) }
    }
    public func all() throws -> [BucketLink] {
        try database.read { try BucketLink.fetchAll($0) }
    }
    public func delete(id: UUID) throws {
        _ = try database.write { try BucketLink.deleteOne($0, key: id.uuidString) }
    }
}

/// CRUD for contacts (PRD §6.4).
public struct ContactRepository: Sendable {
    private let database: any DatabaseWriter
    public init(database: any DatabaseWriter) { self.database = database }

    public func upsert(_ contact: Contact) throws {
        try database.write { try contact.save($0) }
    }
    public func fetch(id: UUID) throws -> Contact? {
        try database.read { try Contact.fetchOne($0, key: id.uuidString) }
    }
    public func all() throws -> [Contact] {
        try database.read { try Contact.fetchAll($0) }
    }
    public func delete(id: UUID) throws {
        _ = try database.write { try Contact.deleteOne($0, key: id.uuidString) }
    }
}

/// CRUD for synced calendar events (PRD §6.5). Keyed by the Graph event id (`String`).
public struct CalendarEventRepository: Sendable {
    private let database: any DatabaseWriter
    public init(database: any DatabaseWriter) { self.database = database }

    public func upsert(_ event: CalendarEvent) throws {
        try database.write { try event.save($0) }
    }
    public func fetch(id: String) throws -> CalendarEvent? {
        try database.read { try CalendarEvent.fetchOne($0, key: id) }
    }
    public func all() throws -> [CalendarEvent] {
        try database.read { try CalendarEvent.fetchAll($0) }
    }
    public func delete(id: String) throws {
        _ = try database.write { try CalendarEvent.deleteOne($0, key: id) }
    }
}

/// CRUD for assembled prep briefs (PRD §6.6).
public struct PrepBriefRepository: Sendable {
    private let database: any DatabaseWriter
    public init(database: any DatabaseWriter) { self.database = database }

    public func upsert(_ brief: PrepBrief) throws {
        try database.write { try brief.save($0) }
    }
    public func fetch(id: UUID) throws -> PrepBrief? {
        try database.read { try PrepBrief.fetchOne($0, key: id.uuidString) }
    }
    public func all() throws -> [PrepBrief] {
        try database.read { try PrepBrief.fetchAll($0) }
    }
    public func delete(id: UUID) throws {
        _ = try database.write { try PrepBrief.deleteOne($0, key: id.uuidString) }
    }
}

/// CRUD for generated assets (PRD §6.8).
public struct AssetRepository: Sendable {
    private let database: any DatabaseWriter
    public init(database: any DatabaseWriter) { self.database = database }

    public func upsert(_ asset: Asset) throws {
        try database.write { try asset.save($0) }
    }
    public func fetch(id: UUID) throws -> Asset? {
        try database.read { try Asset.fetchOne($0, key: id.uuidString) }
    }
    public func all() throws -> [Asset] {
        try database.read { try Asset.fetchAll($0) }
    }
    public func delete(id: UUID) throws {
        _ = try database.write { try Asset.deleteOne($0, key: id.uuidString) }
    }
}
