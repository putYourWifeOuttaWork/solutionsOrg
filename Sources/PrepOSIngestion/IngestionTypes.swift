import Foundation
import PrepOSCore
import PrepOSBucketing

// Public types for the capture→file pipeline (PRD C1, C2). The coordinator turns raw captured
// bytes into filed `Item`s (or triage entries), abstracting persistence behind `IngestionStore`
// so the pipeline is unit-testable without a database.

/// One captured artifact awaiting ingestion (PRD C1.1–C1.4). The bytes are the raw file or
/// pasted text; the coordinator parses, embeds, classifies, and persists it.
public struct CaptureInput: Sendable {
    public var data: Data
    /// Original filename (drives the parser and the fallback title). Use a `.txt` name for
    /// pasted plain text.
    public var filename: String
    public var capturedVia: CaptureMethod

    public init(data: Data, filename: String, capturedVia: CaptureMethod) {
        self.data = data
        self.filename = filename
        self.capturedVia = capturedVia
    }

    /// Convenience for pasted/typed plain text (PRD C1.2).
    public static func text(_ text: String, filename: String = "capture.txt",
                            capturedVia: CaptureMethod = .paste) -> CaptureInput {
        CaptureInput(data: Data(text.utf8), filename: filename, capturedVia: capturedVia)
    }
}

/// What happened to one captured item.
public struct IngestionResult: Sendable, Equatable {
    public let item: Item
    public let disposition: Disposition

    /// The routing outcome (PRD §8 step 5 + the single-vs-bulk rule, C2.2–C2.5).
    public enum Disposition: Sendable, Equatable {
        /// Confident, clear winner — filed silently to a bucket (PRD C2.2).
        case autoFiled(bucketId: UUID, score: Double)
        /// Ambiguous — parked in the Unsorted bucket with a pending triage entry. `interruptNow`
        /// is true for a single capture (interrupt the user now) and false in a bulk operation
        /// (defer to the Needs-Sorting inbox) — PRD C2.3/C2.4.
        case triaged(triageItemId: UUID, candidates: [ScoredBucket], interruptNow: Bool)
        /// Nothing fit — parked in Unsorted with a pending "propose new bucket" triage entry
        /// (PRD C2.5). `interruptNow` follows the same single-vs-bulk rule.
        case newBucketProposed(triageItemId: UUID, topScore: Double, interruptNow: Bool)
    }

    public init(item: Item, disposition: Disposition) {
        self.item = item
        self.disposition = disposition
    }
}

/// Persistence (and current-state) seam for the coordinator. The app provides a GRDB-backed
/// implementation (`PrepOSPersistence`); tests provide an in-memory fake. Keeping this a
/// protocol means the ingestion logic carries no database dependency and stays testable.
public protocol IngestionStore: Sendable {
    /// Current bucket prototypes keyed by bucket id, built from member items' embeddings
    /// (centroid + exemplars). Used to score a new capture against existing buckets.
    func prototypes() async throws -> [UUID: BucketPrototype]

    /// The id of the system "Unsorted" bucket, creating it if absent. Not-yet-filed items home
    /// here (every `Item` requires a home bucket) until the user resolves their triage entry.
    func unsortedBucketId() async throws -> UUID

    /// Persist a captured item together with its embedding vector.
    func persist(item: Item, embedding: [Double]) async throws

    /// Queue a triage entry for the Needs-Sorting inbox.
    func enqueue(_ triage: TriageItem) async throws
}
