import Foundation
import GRDB

/// Owns the GRDB schema for every PRD §6 entity plus `item_embeddings`. UUIDs are stored as
/// `TEXT` (`uuidString`), enums as their `String` `rawValue`, `Date` as fractional-second
/// ISO-8601 `TEXT` (the formatter pinned in `Records.swift`), and composite/array fields
/// (`attendees`, `sources`, `candidateBuckets`)
/// as JSON `TEXT` columns. Foreign keys are declared where natural and `PRAGMA foreign_keys`
/// is on (GRDB enables it by default), so cascade deletes (e.g. item → embedding) work.
public enum PrepOSSchema {

    /// A configured `DatabaseMigrator` with one registered migration, `"v1"`, creating all
    /// tables. Idempotent — safe to run on every open; GRDB skips already-applied migrations.
    public static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "buckets") { t in
                t.primaryKey("id", .text)
                t.column("type", .text).notNull()
                t.column("name", .text).notNull()
                t.column("sfdcId", .text)
                t.column("altifyOppId", .text)
                t.column("status", .text).notNull()
                t.column("createdAt", .text).notNull()
                t.column("updatedAt", .text).notNull()
            }

            try db.create(table: "items") { t in
                t.primaryKey("id", .text)
                t.column("type", .text).notNull()
                t.column("title", .text).notNull()
                t.column("body", .text).notNull()
                t.column("sourcePath", .text)
                t.column("homeBucketId", .text).notNull()
                    .references("buckets", onDelete: .cascade)
                t.column("confidence", .double).notNull()
                t.column("capturedVia", .text).notNull()
                t.column("createdAt", .text).notNull()
            }
            try db.create(index: "idx_items_homeBucketId", on: "items", columns: ["homeBucketId"])

            try db.create(table: "bucket_links") { t in
                t.primaryKey("id", .text)
                t.column("fromBucketId", .text).notNull()
                    .references("buckets", onDelete: .cascade)
                t.column("toBucketId", .text).notNull()
                    .references("buckets", onDelete: .cascade)
                t.column("relationType", .text).notNull()
                t.column("weight", .double).notNull()
                t.column("origin", .text).notNull()
            }

            try db.create(table: "contacts") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("email", .text)
                t.column("domain", .text)
                t.column("sfdcContactId", .text)
                t.column("linkedBucketId", .text)
                    .references("buckets", onDelete: .setNull)
            }

            try db.create(table: "calendar_events") { t in
                t.primaryKey("id", .text)            // Graph event id (String)
                t.column("title", .text).notNull()
                t.column("start", .text).notNull()
                t.column("end", .text).notNull()
                t.column("organizerEmail", .text).notNull()
                t.column("attendees", .text).notNull()   // JSON [EventAttendee]
                t.column("teamsLink", .text)
                t.column("resolvedBucketId", .text)
                    .references("buckets", onDelete: .setNull)
                t.column("resolutionConfidence", .double).notNull()
                t.column("prepBriefId", .text)
            }

            try db.create(table: "prep_briefs") { t in
                t.primaryKey("id", .text)
                t.column("eventId", .text).notNull()
                t.column("generatedAt", .text).notNull()
                t.column("content", .text).notNull()
                t.column("sources", .text).notNull()     // JSON [SourceRef]
                t.column("status", .text).notNull()
            }

            try db.create(table: "triage_items") { t in
                t.primaryKey("id", .text)
                t.column("itemId", .text).notNull()
                    .references("items", onDelete: .cascade)
                t.column("candidateBuckets", .text).notNull()   // JSON [ScoredBucket]
                t.column("rationale", .text)
                t.column("reason", .text).notNull()
                t.column("status", .text).notNull()
            }
            try db.create(index: "idx_triage_status", on: "triage_items", columns: ["status"])

            try db.create(table: "assets") { t in
                t.primaryKey("id", .text)
                t.column("bucketId", .text)
                    .references("buckets", onDelete: .setNull)
                t.column("eventId", .text)
                t.column("kind", .text).notNull()
                t.column("filePath", .text).notNull()
                t.column("createdAt", .text).notNull()
            }

            // Item embeddings: raw vector as a BLOB (MVP computes similarity in Swift; the
            // shape is additive for a later sqlite-vec virtual table). Cascades with its item.
            try db.create(table: "item_embeddings") { t in
                t.primaryKey("itemId", .text)
                    .references("items", onDelete: .cascade)
                t.column("vector", .blob).notNull()
            }
        }
        return migrator
    }

    /// Run all pending migrations on `writer` (a `DatabaseQueue`/`DatabasePool`).
    public static func migrate(_ writer: any DatabaseWriter) throws {
        try migrator().migrate(writer)
    }
}
