import XCTest
import PrepOSCore
@testable import PrepOSBucketing

/// Constitution boundary (CLAUDE.md §1; security constitution §3–4): the full
/// embed → score → decide → graph path runs entirely on-device with the deterministic fake,
/// with no network and no secret dependency. A runtime smoke test that the deterministic path
/// is fully synchronous-local; the no-network/no-secret guarantee is also enforced at the
/// link level (this target links only PrepOSCore + Foundation).
final class ConstitutionBoundaryTests: XCTestCase {

    func testEndToEndOnDevicePathHasNoNetworkOrSecretDependency() async throws {
        let service = DeterministicEmbeddingService()
        let bucketId = UUID()
        let relatedId = UUID()

        // Embed seed text and build a prototype — purely local.
        let seed = try await service.embed("Acme Corp Q3 renewal opportunity")
        var index = PrototypeIndex()
        index.setPrototype(
            BucketPrototype(exemplars: [LabeledVector(label: UUID(), vector: seed)]),
            for: bucketId
        )

        // Score + decide a near-identical item — exercises the real FilingDecider.
        let item = try await service.embed("Acme Corp Q3 renewal opportunity follow-up")
        let decision = index.decide(for: item, config: .default)
        switch decision {
        case .autoFile, .ambiguous, .proposeNewBucket:
            break   // any valid decision proves the path completed locally
        }

        // Learning on correction — pure, local.
        let learned = index.prototypes[bucketId]!.learning(
            LabeledVector(label: UUID(), vector: item)
        )
        index.setPrototype(learned, for: bucketId)

        // Graph traversal — pure, local.
        let graph = BucketGraph(links: [
            BucketLink(
                fromBucketId: bucketId,
                toBucketId: relatedId,
                relationType: .accountOpportunity,
                weight: 0.8,
                origin: .auto
            )
        ])
        let neighbors = graph.neighbors(of: bucketId, depth: 1, weightFloor: 0.5)
        XCTAssertEqual(neighbors, [Neighbor(bucketId: relatedId, hops: 1)])
    }
}
