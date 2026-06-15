import XCTest
import GRDB
@testable import PrepOSPersistence

/// PRD §6 schema (`docs/design-notes/persistence.md` §4 tests 1–3): the migrator creates
/// every entity table plus `item_embeddings`, is idempotent, and shapes JSON columns as TEXT.
final class MigrationTests: XCTestCase {

    private func migratedQueue() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()   // :memory:
        try PrepOSSchema.migrate(queue)
        return queue
    }

    func testMigrationCreatesAllTables() throws {
        let queue = try migratedQueue()
        let expected = [
            "buckets", "items", "bucket_links", "contacts", "calendar_events",
            "prep_briefs", "triage_items", "assets", "item_embeddings",
        ]
        try queue.read { db in
            for table in expected {
                XCTAssertTrue(try db.tableExists(table), "missing table \(table)")
            }
        }
    }

    func testMigrationIsIdempotent() throws {
        let queue = try DatabaseQueue()
        XCTAssertNoThrow(try PrepOSSchema.migrate(queue))
        XCTAssertNoThrow(try PrepOSSchema.migrate(queue))
        try queue.read { db in
            XCTAssertTrue(try db.tableExists("buckets"))
        }
    }

    func testJSONBearingColumnsAreText() throws {
        let queue = try migratedQueue()
        try queue.read { db in
            let cols = try db.columns(in: "calendar_events")
            let attendees = try XCTUnwrap(cols.first { $0.name == "attendees" })
            XCTAssertEqual(attendees.type.uppercased(), "TEXT")
        }
    }
}
