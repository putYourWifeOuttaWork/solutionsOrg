import XCTest
import GRDB
import PrepOSCore
@testable import PrepOSPersistence

/// Repository CRUD round-trips over an in-memory GRDB queue (`docs/design-notes/persistence.md`
/// §4 tests 4–10). No files, no network, no Keychain.
final class RepositoryTests: XCTestCase {

    private func freshQueue() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try PrepOSSchema.migrate(queue)
        return queue
    }

    /// A whole-second date so ISO-8601 TEXT storage round-trips exactly through `Equatable`
    /// (the date format preserves seconds; sub-second precision is intentionally not stored).
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Buckets (test 4, 9)

    func testBucketUpsertFetchRoundTrip() throws {
        let queue = try freshQueue()
        let repo = BucketRepository(database: queue)
        let bucket = Bucket(
            type: .opportunity,
            name: "Acme Q3 Renewal",
            sfdcId: "006xx",
            altifyOppId: "altf-1",
            status: .active,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        try repo.upsert(bucket)
        XCTAssertEqual(try repo.fetch(id: bucket.id), bucket)
    }

    func testBucketUpsertUpdatesInPlaceAndDelete() throws {
        let queue = try freshQueue()
        let repo = BucketRepository(database: queue)
        var bucket = Bucket(type: .account, name: "Acme")
        try repo.upsert(bucket)
        bucket.name = "Acme Corp"
        bucket.status = .archived
        try repo.upsert(bucket)

        XCTAssertEqual(try repo.all().count, 1)
        XCTAssertEqual(try repo.fetch(id: bucket.id)?.name, "Acme Corp")
        XCTAssertNil(try repo.fetch(id: UUID()))

        XCTAssertEqual(try repo.active().count, 0)   // archived
        try repo.delete(id: bucket.id)
        XCTAssertNil(try repo.fetch(id: bucket.id))
    }

    func testBucketActiveFiltersByStatus() throws {
        let queue = try freshQueue()
        let repo = BucketRepository(database: queue)
        let active = Bucket(type: .account, name: "Live", status: .active)
        let archived = Bucket(type: .account, name: "Old", status: .archived)
        try repo.upsert(active)
        try repo.upsert(archived)
        XCTAssertEqual(try repo.active().map(\.id), [active.id])
    }

    // MARK: - Items (test 5, 6, 10)

    func testItemsInBucketNewestFirst() throws {
        let queue = try freshQueue()
        let bucketRepo = BucketRepository(database: queue)
        let itemRepo = ItemRepository(database: queue)
        let bucketA = Bucket(type: .project, name: "A")
        let bucketB = Bucket(type: .project, name: "B")
        try bucketRepo.upsert(bucketA)
        try bucketRepo.upsert(bucketB)

        let older = Item(type: .note, title: "older", body: "x", homeBucketId: bucketA.id,
                         confidence: 0.9, capturedVia: .paste,
                         createdAt: Date(timeIntervalSince1970: 100))
        let newer = Item(type: .note, title: "newer", body: "y", homeBucketId: bucketA.id,
                         confidence: 0.9, capturedVia: .paste,
                         createdAt: Date(timeIntervalSince1970: 200))
        let other = Item(type: .note, title: "other", body: "z", homeBucketId: bucketB.id,
                         confidence: 0.9, capturedVia: .paste,
                         createdAt: Date(timeIntervalSince1970: 150))
        try itemRepo.upsert(older)
        try itemRepo.upsert(newer)
        try itemRepo.upsert(other)

        let inA = try itemRepo.items(inBucket: bucketA.id)
        XCTAssertEqual(inA.map(\.id), [newer.id, older.id])
        XCTAssertEqual(try itemRepo.fetch(id: newer.id), newer)
    }

    func testEmbeddingBlobRoundTrip() throws {
        let queue = try freshQueue()
        let bucketRepo = BucketRepository(database: queue)
        let itemRepo = ItemRepository(database: queue)
        let bucket = Bucket(type: .topic, name: "T")
        try bucketRepo.upsert(bucket)
        let item = Item(type: .note, title: "t", body: "b", homeBucketId: bucket.id,
                        confidence: 1, capturedVia: .hotkey)
        try itemRepo.upsert(item)

        let vector: [Double] = [0.1, -0.2, 3.14159, 0, 1e-9]
        try itemRepo.setEmbedding(ItemEmbedding(itemId: item.id, vector: vector))
        let loaded = try XCTUnwrap(try itemRepo.embedding(forItem: item.id))
        XCTAssertEqual(loaded.vector, vector)   // bit-for-bit
        XCTAssertEqual(loaded.itemId, item.id)
    }

    func testDeletingItemCascadesEmbedding() throws {
        let queue = try freshQueue()
        let bucketRepo = BucketRepository(database: queue)
        let itemRepo = ItemRepository(database: queue)
        let bucket = Bucket(type: .topic, name: "T")
        try bucketRepo.upsert(bucket)
        let item = Item(type: .note, title: "t", body: "b", homeBucketId: bucket.id,
                        confidence: 1, capturedVia: .hotkey)
        try itemRepo.upsert(item)
        try itemRepo.setEmbedding(ItemEmbedding(itemId: item.id, vector: [1, 2, 3]))

        try itemRepo.delete(id: item.id)
        XCTAssertNil(try itemRepo.embedding(forItem: item.id))
    }

    // MARK: - Triage (test 7) — JSON candidateBuckets

    func testTriagePendingDecodesCandidateBuckets() throws {
        let queue = try freshQueue()
        let bucketRepo = BucketRepository(database: queue)
        let itemRepo = ItemRepository(database: queue)
        let triageRepo = TriageRepository(database: queue)
        let bucket = Bucket(type: .topic, name: "T")
        try bucketRepo.upsert(bucket)
        let item = Item(type: .note, title: "t", body: "b", homeBucketId: bucket.id,
                        confidence: 0.4, capturedVia: .share)
        try itemRepo.upsert(item)

        let candidates = [
            ScoredBucket(bucketId: bucket.id, score: 0.6),
            ScoredBucket(bucketId: UUID(), score: 0.55),
        ]
        let pending = TriageItem(itemId: item.id, candidateBuckets: candidates,
                                 rationale: "two close", reason: .ambiguousTwoClose,
                                 status: .pending)
        let resolved = TriageItem(itemId: item.id, candidateBuckets: [],
                                  reason: .noMatch, status: .resolved)
        try triageRepo.upsert(pending)
        try triageRepo.upsert(resolved)

        let onlyPending = try triageRepo.pending()
        XCTAssertEqual(onlyPending.map(\.id), [pending.id])
        XCTAssertEqual(onlyPending.first?.candidateBuckets, candidates)
        XCTAssertEqual(try triageRepo.fetch(id: resolved.id)?.status, .resolved)
    }

    // MARK: - JSON columns on CalendarEvent / PrepBrief (test 8)

    func testCalendarEventAttendeesRoundTrip() throws {
        let queue = try freshQueue()
        let repo = CalendarEventRepository(database: queue)
        let event = CalendarEvent(
            id: "graph-evt-1",
            title: "QBR",
            start: Date(timeIntervalSince1970: 1000),
            end: Date(timeIntervalSince1970: 4600),
            organizerEmail: "rep@altify.com",
            attendees: [
                EventAttendee(name: "Ann", email: "ann@acme.com", rsvp: .accepted),
                EventAttendee(name: "Bob", email: "bob@acme.com", rsvp: .tentative,
                              contactId: UUID()),
            ],
            teamsLink: "https://teams",
            resolutionConfidence: 0.7
        )
        try repo.upsert(event)
        XCTAssertEqual(try repo.fetch(id: event.id), event)
    }

    func testPrepBriefSourcesRoundTrip() throws {
        let queue = try freshQueue()
        let repo = PrepBriefRepository(database: queue)
        let brief = PrepBrief(
            eventId: "graph-evt-1",
            generatedAt: fixedDate,
            content: "# Brief",
            sources: [
                SourceRef(kind: .localItem, label: "note", reference: UUID().uuidString),
                SourceRef(kind: .altifyRecord, label: "opp", reference: "006xx"),
                SourceRef(kind: .webSource, label: "site", reference: "https://x"),
            ],
            status: .fresh
        )
        try repo.upsert(brief)
        XCTAssertEqual(try repo.fetch(id: brief.id), brief)
    }

    // MARK: - Remaining thin repos

    func testContactBucketLinkAssetRoundTrip() throws {
        let queue = try freshQueue()
        let bucketRepo = BucketRepository(database: queue)
        let b1 = Bucket(type: .account, name: "A")
        let b2 = Bucket(type: .opportunity, name: "O")
        try bucketRepo.upsert(b1)
        try bucketRepo.upsert(b2)

        let contactRepo = ContactRepository(database: queue)
        let contact = Contact(name: "Ann", email: "ann@acme.com", domain: "acme.com",
                              linkedBucketId: b1.id)
        try contactRepo.upsert(contact)
        XCTAssertEqual(try contactRepo.fetch(id: contact.id), contact)
        XCTAssertEqual(try contactRepo.all().count, 1)

        let linkRepo = BucketLinkRepository(database: queue)
        let link = BucketLink(fromBucketId: b1.id, toBucketId: b2.id,
                              relationType: .accountOpportunity, weight: 0.8, origin: .auto)
        try linkRepo.upsert(link)
        XCTAssertEqual(try linkRepo.fetch(id: link.id), link)

        let assetRepo = AssetRepository(database: queue)
        let asset = Asset(bucketId: b1.id, kind: .agenda, filePath: "/tmp/a.md",
                          createdAt: fixedDate)
        try assetRepo.upsert(asset)
        XCTAssertEqual(try assetRepo.fetch(id: asset.id), asset)
        try assetRepo.delete(id: asset.id)
        XCTAssertNil(try assetRepo.fetch(id: asset.id))
    }
}
