import Foundation
import PrepOSCore

/// A reachable bucket plus the hop distance at which it was first reached (1 = direct).
public struct Neighbor: Sendable, Equatable, Hashable {
    public var bucketId: UUID
    public var hops: Int
    public init(bucketId: UUID, hops: Int) {
        self.bucketId = bucketId
        self.hops = hops
    }
}

/// An adjacency view over `[BucketLink]` (PRD §6.3) for weight-pruned, depth-bounded
/// traversal during prep composition (PRD C3.2). Built once from links, then queried. Pure
/// in-memory graph — no I/O. Links are treated as **undirected** (each edge connects both
/// endpoints), matching the "undirected semantically" note on `BucketLink`.
public struct BucketGraph: Sendable {
    /// `bucketId → [(neighbor, weight)]`, both directions of every link.
    private let adjacency: [UUID: [(neighbor: UUID, weight: Double)]]

    public init(links: [BucketLink]) {
        var adjacency: [UUID: [(neighbor: UUID, weight: Double)]] = [:]
        for link in links {
            adjacency[link.fromBucketId, default: []]
                .append((link.toBucketId, link.weight))
            adjacency[link.toBucketId, default: []]
                .append((link.fromBucketId, link.weight))
        }
        self.adjacency = adjacency
    }

    /// Buckets reachable from `bucket` within `depth` hops, traversing only edges whose
    /// `weight >= weightFloor`. BFS; each neighbor is returned once at its **shortest** hop
    /// distance; the origin is excluded. `depth <= 0` → empty.
    /// - Parameters:
    ///   - depth: max hops (PRD default `AppConfig.linkTraversalDepth` = 1).
    ///   - weightFloor: minimum edge weight to traverse (prunes weak links).
    public func neighbors(of bucket: UUID, depth: Int, weightFloor: Double) -> [Neighbor] {
        guard depth > 0 else { return [] }

        var firstHop: [UUID: Int] = [bucket: 0]   // shortest hop distance per visited node
        var frontier: [UUID] = [bucket]
        var hop = 0

        while !frontier.isEmpty && hop < depth {
            hop += 1
            var next: [UUID] = []
            for node in frontier {
                for edge in adjacency[node] ?? [] where edge.weight >= weightFloor {
                    if firstHop[edge.neighbor] == nil {
                        firstHop[edge.neighbor] = hop
                        next.append(edge.neighbor)
                    }
                }
            }
            frontier = next
        }

        // Exclude the origin; deterministic order: by hop, then by id, for unit-testability.
        return firstHop
            .filter { $0.key != bucket }
            .map { Neighbor(bucketId: $0.key, hops: $0.value) }
            .sorted { ($0.hops, $0.bucketId.uuidString) < ($1.hops, $1.bucketId.uuidString) }
    }
}
