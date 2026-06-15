import XCTest
import PrepOSCore
@testable import PrepOSBucketing

/// `BucketGraph` weight-pruned, depth-bounded BFS (design note §4; PRD C3.2).
final class BucketGraphTests: XCTestCase {

    private func link(_ from: UUID, _ to: UUID, _ weight: Double) -> BucketLink {
        BucketLink(
            fromBucketId: from,
            toBucketId: to,
            relationType: .manual,
            weight: weight,
            origin: .manual
        )
    }

    func testDepthOneReturnsDirectNeighborsOnly() {
        let a = UUID(), b = UUID(), c = UUID()
        let graph = BucketGraph(links: [link(a, b, 0.9), link(b, c, 0.9)])
        let neighbors = graph.neighbors(of: a, depth: 1, weightFloor: 0.1)
        XCTAssertEqual(neighbors, [Neighbor(bucketId: b, hops: 1)])
    }

    func testDepthTwoIncludesSecondHopAndExcludesOrigin() {
        let a = UUID(), b = UUID(), c = UUID()
        let graph = BucketGraph(links: [link(a, b, 0.9), link(b, c, 0.9)])
        let neighbors = graph.neighbors(of: a, depth: 2, weightFloor: 0.1)
        XCTAssertEqual(Set(neighbors), [Neighbor(bucketId: b, hops: 1), Neighbor(bucketId: c, hops: 2)])
        XCTAssertFalse(neighbors.contains { $0.bucketId == a })
    }

    func testEdgeBelowWeightFloorIsNotTraversed() {
        let a = UUID(), b = UUID(), c = UUID()
        // a—b is strong; b—c is weak. With a high floor, c is unreachable.
        let graph = BucketGraph(links: [link(a, b, 0.9), link(b, c, 0.2)])
        let neighbors = graph.neighbors(of: a, depth: 3, weightFloor: 0.5)
        XCTAssertEqual(neighbors, [Neighbor(bucketId: b, hops: 1)])
    }

    func testBucketReachableAtMultipleHopsReportedAtShortest() {
        let a = UUID(), b = UUID(), c = UUID()
        // c is direct (1 hop) and also via b (2 hops) → must be reported once at hops==1.
        let graph = BucketGraph(links: [link(a, b, 0.9), link(b, c, 0.9), link(a, c, 0.9)])
        let neighbors = graph.neighbors(of: a, depth: 2, weightFloor: 0.1)
        let cEntries = neighbors.filter { $0.bucketId == c }
        XCTAssertEqual(cEntries, [Neighbor(bucketId: c, hops: 1)])
    }

    func testDepthZeroIsEmpty() {
        let a = UUID(), b = UUID()
        let graph = BucketGraph(links: [link(a, b, 0.9)])
        XCTAssertTrue(graph.neighbors(of: a, depth: 0, weightFloor: 0.1).isEmpty)
    }

    func testWeightFloorAboveAllWeightsIsEmpty() {
        let a = UUID(), b = UUID()
        let graph = BucketGraph(links: [link(a, b, 0.9)])
        XCTAssertTrue(graph.neighbors(of: a, depth: 2, weightFloor: 1.5).isEmpty)
    }

    func testUnknownOriginIsEmpty() {
        let a = UUID(), b = UUID()
        let graph = BucketGraph(links: [link(a, b, 0.9)])
        XCTAssertTrue(graph.neighbors(of: UUID(), depth: 2, weightFloor: 0.1).isEmpty)
    }

    func testCycleTerminatesAndVisitsEachNodeOnce() {
        let a = UUID(), b = UUID(), c = UUID()
        let graph = BucketGraph(links: [link(a, b, 0.9), link(b, c, 0.9), link(c, a, 0.9)])
        let neighbors = graph.neighbors(of: a, depth: 10, weightFloor: 0.1)
        XCTAssertEqual(Set(neighbors), [Neighbor(bucketId: b, hops: 1), Neighbor(bucketId: c, hops: 1)])
    }
}
