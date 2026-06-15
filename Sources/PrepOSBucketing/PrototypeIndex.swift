import Foundation
import PrepOSCore

/// Holds the live `bucketId → BucketPrototype` map and turns an item vector into ranked
/// `ScoredBucket`s (from `PrepOSCore`), then into a `FilingDecision` via the **real**
/// `FilingDecider` (PrepOSCore). This piece adds no decision logic of its own — the
/// double-threshold + margin rule stays single-sourced in `PrepOSCore.FilingDecider`.
public struct PrototypeIndex: Sendable {
    public private(set) var prototypes: [UUID: BucketPrototype]

    public init(prototypes: [UUID: BucketPrototype] = [:]) {
        self.prototypes = prototypes
    }

    /// Upsert a bucket's prototype (e.g. after `learning`).
    public mutating func setPrototype(_ prototype: BucketPrototype, for bucketId: UUID) {
        prototypes[bucketId] = prototype
    }

    /// Score `vector` against every prototype → `[ScoredBucket]`, sorted descending.
    /// Empty when there are no prototypes (cold start → the decider yields
    /// `.proposeNewBucket`).
    ///
    /// An optional `boosts: [UUID: Double]` lets a caller fold in a pre-computed entity-
    /// resolution boost (PRD §8 step 4) **without** this piece making any network/MCP call —
    /// the boost is supplied by the caller; each boosted score is clamped to `[-1, 1]`.
    public func scored(for vector: [Double], boosts: [UUID: Double] = [:]) -> [ScoredBucket] {
        prototypes
            .map { bucketId, prototype in
                let raw = prototype.score(vector) + (boosts[bucketId] ?? 0)
                return ScoredBucket(bucketId: bucketId, score: min(1, max(-1, raw)))
            }
            .sorted { $0.score > $1.score }
    }

    /// Full path: score `vector`, then route via `FilingDecider.decide(candidates:config:)`.
    /// `boosts` defaults to empty (no boost), keeping the no-network guarantee while leaving
    /// a seam for the later entity-resolution piece. This never re-implements the thresholds.
    public func decide(
        for vector: [Double],
        config: AppConfig,
        boosts: [UUID: Double] = [:]
    ) -> FilingDecision {
        FilingDecider.decide(candidates: scored(for: vector, boosts: boosts), config: config)
    }
}
