import Foundation
import PrepOSCore
import PrepOSParsing
import PrepOSBucketing

/// The capture→file pipeline (PRD §8, C1.6, C2). For each captured artifact it parses the text,
/// embeds it on-device, scores it against existing bucket prototypes, and applies the
/// double-threshold + margin decision (`FilingDecider`, via `PrototypeIndex`). Confident matches
/// are filed silently; ambiguous or no-match captures are parked in the Unsorted bucket with a
/// pending triage entry. The single-vs-bulk rule (C2.3/C2.4) decides whether triage should
/// interrupt the user now (single capture) or defer to the Needs-Sorting inbox (bulk).
///
/// Stateless and `Sendable`: all current state (prototypes, the Unsorted bucket) and all side
/// effects flow through the injected `IngestionStore`, so the pipeline runs in tests with an
/// in-memory fake and no Xcode-only frameworks.
public struct IngestionCoordinator: Sendable {
    private let parser: ParserRegistry
    private let embedder: any EmbeddingService
    private let store: any IngestionStore
    private let config: AppConfig

    public init(
        parser: ParserRegistry = .makeDefault(),
        embedder: any EmbeddingService,
        store: any IngestionStore,
        config: AppConfig = .default
    ) {
        self.parser = parser
        self.embedder = embedder
        self.store = store
        self.config = config
    }

    /// Ingest a batch of captures, returning one result per input in order. A batch larger than
    /// `config.nBulk` is treated as a **bulk** operation: ambiguous/no-match items are deferred
    /// to the Needs-Sorting inbox rather than interrupting the user (PRD C2.4).
    @discardableResult
    public func ingest(_ inputs: [CaptureInput]) async throws -> [IngestionResult] {
        guard !inputs.isEmpty else { return [] }

        let isBulk = inputs.count > config.nBulk
        let index = PrototypeIndex(prototypes: try await store.prototypes())

        var results: [IngestionResult] = []
        results.reserveCapacity(inputs.count)
        for input in inputs {
            results.append(try await ingestOne(input, index: index, isBulk: isBulk))
        }
        return results
    }

    /// Ingest a single capture (PRD C1.2). Always treated as a single (interrupting) capture.
    @discardableResult
    public func ingest(_ input: CaptureInput) async throws -> IngestionResult {
        let index = PrototypeIndex(prototypes: try await store.prototypes())
        return try await ingestOne(input, index: index, isBulk: false)
    }

    private func ingestOne(_ input: CaptureInput, index: PrototypeIndex, isBulk: Bool) async throws -> IngestionResult {
        let text = try parser.parse(input.data, filename: input.filename)
        let vector = try await embedder.embed(text)
        let title = CaptureNormalizer.title(forText: text, filename: input.filename)
        let type = CaptureNormalizer.itemType(forFilename: input.filename)

        func makeItem(homeBucketId: UUID, confidence: Double) -> Item {
            Item(type: type, title: title, body: text, sourcePath: input.filename,
                 homeBucketId: homeBucketId, confidence: confidence, capturedVia: input.capturedVia)
        }

        switch index.decide(for: vector, config: config) {
        case let .autoFile(bucketId, score):
            let item = makeItem(homeBucketId: bucketId, confidence: score)
            try await store.persist(item: item, embedding: vector)
            return IngestionResult(item: item, disposition: .autoFiled(bucketId: bucketId, score: score))

        case let .ambiguous(candidates):
            let item = makeItem(homeBucketId: try await store.unsortedBucketId(),
                                confidence: candidates.first?.score ?? 0)
            try await store.persist(item: item, embedding: vector)
            let triage = TriageItem(itemId: item.id, candidateBuckets: candidates,
                                    reason: isBulk ? .bulkDeferred : .ambiguousTwoClose)
            try await store.enqueue(triage)
            return IngestionResult(item: item, disposition: .triaged(
                triageItemId: triage.id, candidates: candidates, interruptNow: !isBulk))

        case let .proposeNewBucket(topScore):
            let item = makeItem(homeBucketId: try await store.unsortedBucketId(), confidence: topScore)
            try await store.persist(item: item, embedding: vector)
            let triage = TriageItem(itemId: item.id, candidateBuckets: [],
                                    reason: isBulk ? .bulkDeferred : .noMatch)
            try await store.enqueue(triage)
            return IngestionResult(item: item, disposition: .newBucketProposed(
                triageItemId: triage.id, topScore: topScore, interruptNow: !isBulk))
        }
    }
}

/// Pure helpers for deriving an item's title and type from a capture (PRD C1.5/C1.7 — no user
/// input required at capture time).
public enum CaptureNormalizer {
    /// The first non-empty line of the text (trimmed, length-capped), falling back to the
    /// filename stem, then "Untitled".
    public static func title(forText text: String, filename: String, maxLength: Int = 120) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })

        if let line = firstLine, !line.isEmpty {
            return line.count > maxLength ? String(line.prefix(maxLength)).trimmingCharacters(in: .whitespaces) + "…" : line
        }
        let stem = (filename as NSString).deletingPathExtension
        return stem.isEmpty ? "Untitled" : stem
    }

    /// Map a filename to an item type: caption files are transcripts; everything else is a note
    /// (PRD §6.2). Records and assets are produced by other paths, not capture.
    public static func itemType(forFilename filename: String) -> ItemType {
        switch (filename as NSString).pathExtension.lowercased() {
        case "vtt", "srt": return .transcript
        default: return .note
        }
    }
}
