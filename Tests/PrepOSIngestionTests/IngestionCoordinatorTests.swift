import XCTest
@testable import PrepOSIngestion
import PrepOSCore
import PrepOSBucketing

// A deterministic, controllable embedding: every text maps to the same fixed vector, so the
// filing decision is driven entirely by the prototypes we install in the fake store.
private struct FixedEmbedding: EmbeddingService {
    let vector: [Double]
    var dimension: Int { vector.count }
    func embed(_ text: String) async throws -> [Double] { vector }
}

// In-memory IngestionStore — records side effects for assertions.
private final class FakeStore: IngestionStore, @unchecked Sendable {
    var protos: [UUID: BucketPrototype]
    let unsorted: UUID
    private(set) var persisted: [(item: Item, embedding: [Double])] = []
    private(set) var triaged: [TriageItem] = []

    init(prototypes: [UUID: BucketPrototype] = [:], unsorted: UUID = UUID()) {
        self.protos = prototypes
        self.unsorted = unsorted
    }
    func prototypes() async throws -> [UUID: BucketPrototype] { protos }
    func unsortedBucketId() async throws -> UUID { unsorted }
    func persist(item: Item, embedding: [Double]) async throws { persisted.append((item, embedding)) }
    func enqueue(_ triage: TriageItem) async throws { triaged.append(triage) }
}

final class IngestionCoordinatorTests: XCTestCase {
    // Query vector and prototype exemplars chosen so cosine to the query is exactly the comment.
    private let query: [Double] = [1, 0, 0, 0]
    private func proto(_ vec: [Double]) -> BucketPrototype {
        BucketPrototype(exemplars: [LabeledVector(label: UUID(), vector: vec)])
    }
    private func coordinator(_ store: FakeStore) -> IngestionCoordinator {
        IngestionCoordinator(embedder: FixedEmbedding(vector: query), store: store)
    }

    func testConfidentMatchAutoFilesSilently() async throws {
        let bucket = UUID()
        let store = FakeStore(prototypes: [bucket: proto([1, 0, 0, 0])])   // cos 1.0
        let result = try await coordinator(store).ingest(.text("Acme renewal call notes"))

        guard case let .autoFiled(bucketId, score) = result.disposition else {
            return XCTFail("expected autoFiled, got \(result.disposition)")
        }
        XCTAssertEqual(bucketId, bucket)
        XCTAssertEqual(score, 1.0, accuracy: 0.001)
        XCTAssertEqual(result.item.homeBucketId, bucket)
        XCTAssertEqual(store.persisted.count, 1)
        XCTAssertEqual(store.persisted.first?.embedding, query)
        XCTAssertTrue(store.triaged.isEmpty, "auto-file must not create a triage entry")
    }

    func testMidBandSingleCaptureInterruptsToTriage() async throws {
        let bucket = UUID()
        let store = FakeStore(prototypes: [bucket: proto([0.6, 0.8, 0, 0])])   // cos 0.6 ∈ [tLow,tHigh)
        let result = try await coordinator(store).ingest(.text("ambiguous note"))

        guard case let .triaged(triageId, candidates, interruptNow) = result.disposition else {
            return XCTFail("expected triaged, got \(result.disposition)")
        }
        XCTAssertTrue(interruptNow, "a single ambiguous capture interrupts now")
        XCTAssertEqual(candidates.first?.bucketId, bucket)
        XCTAssertEqual(result.item.homeBucketId, store.unsorted, "parked in Unsorted")
        XCTAssertEqual(store.triaged.count, 1)
        XCTAssertEqual(store.triaged.first?.id, triageId)
        XCTAssertEqual(store.triaged.first?.reason, .ambiguousTwoClose)
    }

    func testBulkAmbiguousDefersToInboxWithoutInterrupt() async throws {
        let bucket = UUID()
        let store = FakeStore(prototypes: [bucket: proto([0.6, 0.8, 0, 0])])
        // 4 inputs > nBulk (3) → bulk operation.
        let inputs = (0..<4).map { CaptureInput.text("note \($0)") }
        let results = try await coordinator(store).ingest(inputs)

        XCTAssertEqual(results.count, 4)
        for result in results {
            guard case let .triaged(_, _, interruptNow) = result.disposition else {
                return XCTFail("expected triaged, got \(result.disposition)")
            }
            XCTAssertFalse(interruptNow, "bulk ambiguous defers — no interrupt")
        }
        XCTAssertEqual(store.triaged.count, 4)
        XCTAssertEqual(store.triaged.allSatisfy { $0.reason == .bulkDeferred }, true)
    }

    func testThreeCapturesStaysSingleMode() async throws {
        // nBulk default is 3; exactly 3 is NOT > nBulk, so still single (interrupting).
        let store = FakeStore(prototypes: [UUID(): proto([0.6, 0.8, 0, 0])])
        let results = try await coordinator(store).ingest((0..<3).map { CaptureInput.text("n\($0)") })
        for result in results {
            guard case let .triaged(_, _, interruptNow) = result.disposition else {
                return XCTFail("expected triaged")
            }
            XCTAssertTrue(interruptNow)
        }
    }

    func testNoMatchProposesNewBucket() async throws {
        let store = FakeStore(prototypes: [:])   // no buckets exist yet (cold start)
        let result = try await coordinator(store).ingest(.text("totally novel topic"))

        guard case let .newBucketProposed(triageId, topScore, interruptNow) = result.disposition else {
            return XCTFail("expected newBucketProposed, got \(result.disposition)")
        }
        XCTAssertEqual(topScore, 0, accuracy: 0.001)
        XCTAssertTrue(interruptNow)
        XCTAssertEqual(result.item.homeBucketId, store.unsorted)
        XCTAssertEqual(store.triaged.first?.id, triageId)
        XCTAssertEqual(store.triaged.first?.reason, .noMatch)
        XCTAssertTrue(store.triaged.first?.candidateBuckets.isEmpty ?? false)
    }

    func testEmptyBatchDoesNothing() async throws {
        let store = FakeStore()
        let results = try await coordinator(store).ingest([])
        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(store.persisted.isEmpty)
    }

    func testEveryCaptureIsPersisted() async throws {
        // Even ambiguous/no-match captures are stored (nothing is lost) — PRD C1.7.
        let store = FakeStore(prototypes: [:])
        _ = try await coordinator(store).ingest([.text("a"), .text("b")])
        XCTAssertEqual(store.persisted.count, 2)
    }
}

final class CaptureNormalizerTests: XCTestCase {
    func testTitleUsesFirstNonEmptyLine() {
        let title = CaptureNormalizer.title(forText: "\n  Acme Q3 sync  \nmore text", filename: "x.txt")
        XCTAssertEqual(title, "Acme Q3 sync")
    }

    func testTitleFallsBackToFilenameStem() {
        XCTAssertEqual(CaptureNormalizer.title(forText: "   \n  ", filename: "meeting-notes.md"), "meeting-notes")
    }

    func testTitleFallsBackToUntitled() {
        XCTAssertEqual(CaptureNormalizer.title(forText: "", filename: ""), "Untitled")
    }

    func testLongTitleIsTruncated() {
        let long = String(repeating: "a", count: 200)
        let title = CaptureNormalizer.title(forText: long, filename: "x.txt", maxLength: 120)
        XCTAssertEqual(title.count, 121)   // 120 chars + ellipsis
        XCTAssertTrue(title.hasSuffix("…"))
    }

    func testCaptionFilesAreTranscripts() {
        XCTAssertEqual(CaptureNormalizer.itemType(forFilename: "call.vtt"), .transcript)
        XCTAssertEqual(CaptureNormalizer.itemType(forFilename: "call.SRT"), .transcript)
    }

    func testOtherFilesAreNotes() {
        XCTAssertEqual(CaptureNormalizer.itemType(forFilename: "notes.md"), .note)
        XCTAssertEqual(CaptureNormalizer.itemType(forFilename: "doc.pdf"), .note)
    }
}
