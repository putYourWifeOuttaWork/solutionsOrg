import Foundation

/// A bucket paired with a similarity score. Produced by the bucketing engine (PRD §8 step 3)
/// as a filing candidate, and persisted on a `TriageItem` as a ranked suggestion (PRD §6.7) —
/// the same shape flows straight from a decision into triage with no translation.
public struct ScoredBucket: Sendable, Codable, Equatable {
    public var bucketId: UUID
    public var score: Double
    public init(bucketId: UUID, score: Double) {
        self.bucketId = bucketId
        self.score = score
    }
}

/// The routing outcome for a freshly-embedded item (PRD §8 step 5). This is the *pure*
/// score-based decision; the ingestion coordinator turns `.ambiguous`/`.proposeNewBucket`
/// into either a single-capture interrupt or a bulk triage entry (PRD C2.3/C2.4), and the
/// engine attaches an LLM-suggested type/name to a new-bucket proposal (PRD §8 cold start).
public enum FilingDecision: Sendable, Equatable {
    /// Top match is a confident, clear winner — file silently (PRD C2.2).
    case autoFile(bucketId: UUID, score: Double)
    /// Genuinely ambiguous — ranked candidates need user resolution (PRD C2.3).
    case ambiguous(candidates: [ScoredBucket])
    /// Nothing fits — propose creating a new bucket (PRD C2.5). Carries how strong the best
    /// match was so the engine/UI can explain the proposal.
    case proposeNewBucket(topScore: Double)
}

/// The double-threshold + margin decision rule (PRD §8). Pure and exhaustively unit-tested
/// — it owns no embeddings or I/O. Candidates must already include any entity-resolution
/// boost (PRD §8 step 4).
public enum FilingDecider {

    /// Decide where an item should go from its scored candidates and the user's thresholds.
    ///
    /// Rule (PRD §8 step 5), resolving the C2.2 / C2.3 interaction conservatively so a
    /// near-tie never auto-files to the wrong bucket (PRD §15 open question 1 — calibratable):
    /// - no candidates, or best score `< T_low` and far from all → `.proposeNewBucket`
    /// - best score `≥ T_high` **and** a clear margin over the runner-up → `.autoFile`
    /// - otherwise (best in `[T_low, T_high)`, or high but within `T_margin`) → `.ambiguous`
    ///
    /// - Parameter candidates: scored buckets in any order; sorted internally, descending.
    public static func decide(candidates: [ScoredBucket], config: AppConfig) -> FilingDecision {
        let ranked = candidates.sorted { $0.score > $1.score }

        guard let top = ranked.first else {
            return .proposeNewBucket(topScore: 0)
        }

        if top.score < config.tLow {
            return .proposeNewBucket(topScore: top.score)
        }

        let runnerUp = ranked.count > 1 ? ranked[1].score : -.infinity
        let clearMargin = (top.score - runnerUp) >= config.tMargin

        if top.score >= config.tHigh && clearMargin {
            return .autoFile(bucketId: top.bucketId, score: top.score)
        }

        return .ambiguous(candidates: ranked)
    }
}
