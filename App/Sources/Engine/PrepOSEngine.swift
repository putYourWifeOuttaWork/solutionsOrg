import Foundation
import SwiftUI
import PrepOSCore
import PrepOSBucketing
import PrepOSIngestion
import PrepOSPipeline

/// The app's composition root and view-model. Wires the encrypted local store, the on-device
/// embedder, and the `IngestionCoordinator`, and exposes the capture / triage / bucket state
/// SwiftUI renders. Lives on the main actor; all DB work hops to a background task and results
/// are published back.
@MainActor
final class PrepOSEngine: ObservableObject {
    @Published private(set) var buckets: [BucketSummary] = []
    @Published private(set) var needsSorting: [TriageEntry] = []
    @Published private(set) var status: Status = .starting
    @Published private(set) var embedderName = "—"
    /// Transient banner describing the most recent capture outcome.
    @Published var lastOutcome: String?

    enum Status: Equatable {
        case starting
        case ready
        case failed(String)
    }

    private var store: PrepOSStore?
    private var coordinator: IngestionCoordinator?
    private let config = AppConfig.default

    // MARK: Lifecycle

    /// Open the encrypted database, choose a working embedder, and load current state.
    func start() async {
        do {
            let store = try Self.makeStore()
            let ingestionStore = try store.open()
            let (embedder, name) = await Self.makeEmbedder()
            self.store = store
            self.coordinator = IngestionCoordinator(embedder: embedder, store: ingestionStore, config: config)
            self.embedderName = name
            self.status = .ready
            await refresh()
        } catch {
            self.status = .failed(String(describing: error))
        }
    }

    // MARK: Capture

    /// Capture pasted/typed text (PRD C1.2).
    func capture(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await ingest([.text(trimmed, capturedVia: .paste)])
    }

    /// Capture dropped files (PRD C1.1). Unreadable/unsupported files are skipped.
    func capture(urls: [URL]) async {
        let inputs: [CaptureInput] = urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return CaptureInput(data: data, filename: url.lastPathComponent, capturedVia: .dragdrop)
        }
        guard !inputs.isEmpty else { return }
        await ingest(inputs)
    }

    private func ingest(_ inputs: [CaptureInput]) async {
        guard let coordinator, let store else { return }
        do {
            let results = try await coordinator.ingest(inputs)
            try store.persist()
            lastOutcome = Self.summarize(results)
            await refresh()
        } catch {
            lastOutcome = "Capture failed: \(error)"
        }
    }

    // MARK: Triage resolution

    /// File a triaged item into the chosen bucket and clear its triage entry.
    func resolve(_ entry: TriageEntry, toBucket bucketId: UUID) async {
        await mutate {
            try $0.moveItem(entry.itemId, toBucket: bucketId)
            try $0.resolveTriage(entry.id)
        }
    }

    /// Create a new bucket, file the triaged item into it, and clear the triage entry.
    func resolve(_ entry: TriageEntry, intoNewBucket name: String, type: BucketType) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await mutate {
            let bucket = Bucket(type: type, name: trimmed)
            try $0.upsertBucket(bucket)
            try $0.moveItem(entry.itemId, toBucket: bucket.id)
            try $0.resolveTriage(entry.id)
        }
    }

    private func mutate(_ work: (PrepOSStore) throws -> Void) async {
        guard let store else { return }
        do {
            try work(store)
            try store.persist()
            await refresh()
        } catch {
            lastOutcome = "Update failed: \(error)"
        }
    }

    // MARK: State load

    func refresh() async {
        guard let store else { return }
        do {
            let allBuckets = try store.allBuckets()
            let byId = Dictionary(uniqueKeysWithValues: allBuckets.map { ($0.id, $0.name) })

            buckets = try allBuckets
                .map { bucket in
                    BucketSummary(id: bucket.id, name: bucket.name, type: bucket.type,
                                  items: try store.items(inBucket: bucket.id)
                                      .map { ItemRow(id: $0.id, title: $0.title, type: $0.type) })
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            needsSorting = try store.pendingTriage().map { triage in
                TriageEntry(triage: triage,
                            candidates: triage.candidateBuckets.map {
                                ($0.bucketId, byId[$0.bucketId] ?? "Unknown", $0.score)
                            })
            }
        } catch {
            lastOutcome = "Refresh failed: \(error)"
        }
    }

    // MARK: Wiring helpers

    private static func makeStore() throws -> PrepOSStore {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = support.appendingPathComponent("PrepOS", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PrepOSStore(cipherURL: dir.appendingPathComponent("prepos.db.enc"),
                           workingDirectory: dir,
                           secretStore: KeychainSecretStore())
    }

    /// Prefer the on-device `NLContextualEmbedding`; if its model can't load (assets/sandbox),
    /// fall back to the deterministic dev embedder so capture always works.
    private static func makeEmbedder() async -> (any EmbeddingService, String) {
        if let nl = try? ContextualEmbeddingService() {
            do {
                _ = try await nl.embed("probe")
                return (nl, "NLContextualEmbedding")
            } catch { /* fall through */ }
        }
        return (DeterministicEmbeddingService(), "Deterministic (dev)")
    }

    private static func summarize(_ results: [IngestionResult]) -> String {
        let filed = results.filter { if case .autoFiled = $0.disposition { return true }; return false }.count
        let sorting = results.count - filed
        switch (filed, sorting) {
        case (let f, 0): return "Auto-filed \(f) item\(f == 1 ? "" : "s")."
        case (0, let s): return "\(s) item\(s == 1 ? "" : "s") need sorting."
        default: return "Auto-filed \(filed); \(sorting) need sorting."
        }
    }
}

// MARK: View models

struct BucketSummary: Identifiable, Equatable {
    let id: UUID
    let name: String
    let type: BucketType
    let items: [ItemRow]
}

struct ItemRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    let type: ItemType
}

struct TriageEntry: Identifiable {
    let triage: TriageItem
    /// (bucketId, bucketName, score) for each ranked candidate.
    let candidates: [(UUID, String, Double)]

    var id: UUID { triage.id }
    var itemId: UUID { triage.itemId }
    var reason: TriageReason { triage.reason }
}
