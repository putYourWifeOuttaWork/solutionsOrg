import XCTest
import PrepOSCore
@testable import PrepOSBucketing

/// `PrototypeIndex` scoring + integration with the REAL `FilingDecider` (design note §4).
/// Vectors are unit basis vectors so cosine scores are exactly controllable.
final class PrototypeIndexTests: XCTestCase {

    private let config = AppConfig.default   // tHigh 0.82, tLow 0.55, tMargin 0.07

    /// A prototype whose centroid points exactly along the unit vector `v`.
    private func proto(_ v: [Double]) -> BucketPrototype {
        BucketPrototype(exemplars: [LabeledVector(label: UUID(), vector: v)])
    }

    func testAutoFileWhenClearWinnerAboveTHigh() {
        let winner = UUID()
        let other = UUID()
        var index = PrototypeIndex()
        index.setPrototype(proto([1, 0, 0]), for: winner)        // cosine 1.0 to query
        index.setPrototype(proto([0, 1, 0]), for: other)         // cosine 0.0 to query
        let decision = index.decide(for: [1, 0, 0], config: config)
        guard case let .autoFile(bucketId, score) = decision else {
            return XCTFail("expected autoFile, got \(decision)")
        }
        XCTAssertEqual(bucketId, winner)
        XCTAssertEqual(score, 1.0, accuracy: 1e-9)
    }

    func testAmbiguousWhenTopInLowBand() {
        // Query at 45° to a single bucket → cosine ≈ 0.707, inside [tLow, tHigh).
        var index = PrototypeIndex()
        index.setPrototype(proto([1, 0]), for: UUID())
        let decision = index.decide(for: [1, 1], config: config)
        guard case let .ambiguous(candidates) = decision else {
            return XCTFail("expected ambiguous, got \(decision)")
        }
        XCTAssertEqual(candidates.first?.score ?? 0, 0.7071, accuracy: 1e-3)
    }

    func testAmbiguousWhenTwoCandidatesWithinMargin() {
        // Two buckets both very close to the query and to each other → margin rule fires
        // even though scores exceed tHigh.
        let a = UUID(), b = UUID()
        var index = PrototypeIndex()
        index.setPrototype(proto([1, 0]), for: a)
        index.setPrototype(proto([0.999, 0.0447]), for: b)   // ~2.56° apart from a
        let decision = index.decide(for: [1, 0], config: config)
        guard case let .ambiguous(candidates) = decision else {
            return XCTFail("expected ambiguous (margin), got \(decision)")
        }
        XCTAssertEqual(candidates.count, 2)
        XCTAssertGreaterThanOrEqual(candidates[0].score, candidates[1].score)   // descending
    }

    func testProposeNewBucketWhenBestBelowTLow() {
        var index = PrototypeIndex()
        index.setPrototype(proto([1, 0, 0]), for: UUID())
        // Query nearly orthogonal → cosine ≈ 0.196 < tLow.
        let decision = index.decide(for: [0.196, 0.98, 0], config: config)
        guard case let .proposeNewBucket(topScore) = decision else {
            return XCTFail("expected proposeNewBucket, got \(decision)")
        }
        XCTAssertLessThan(topScore, config.tLow)
    }

    func testColdStartEmptyIndexProposesNewBucketWithZeroScore() {
        let index = PrototypeIndex()
        XCTAssertTrue(index.scored(for: [1, 0, 0]).isEmpty)
        let decision = index.decide(for: [1, 0, 0], config: config)
        XCTAssertEqual(decision, .proposeNewBucket(topScore: 0))
    }

    func testScoredIsSortedDescending() {
        var index = PrototypeIndex()
        index.setPrototype(proto([0, 1]), for: UUID())     // lower cosine to query
        index.setPrototype(proto([1, 0]), for: UUID())     // higher cosine to query
        let scored = index.scored(for: [1, 0.3])
        XCTAssertEqual(scored.count, 2)
        XCTAssertGreaterThanOrEqual(scored[0].score, scored[1].score)
    }

    func testBoostRaisesCandidateAndCanFlipToAutoFile() {
        // Single bucket at cosine ≈ 0.707 → ambiguous unboosted. A boost pushes it past
        // tHigh (and it is the only candidate, so margin is clear) → autoFile.
        let target = UUID()
        var index = PrototypeIndex()
        index.setPrototype(proto([1, 0]), for: target)

        let unboosted = index.decide(for: [1, 1], config: config)
        guard case .ambiguous = unboosted else {
            return XCTFail("expected ambiguous unboosted, got \(unboosted)")
        }

        let boosted = index.decide(for: [1, 1], config: config, boosts: [target: 0.3])
        guard case let .autoFile(bucketId, score) = boosted else {
            return XCTFail("expected autoFile after boost, got \(boosted)")
        }
        XCTAssertEqual(bucketId, target)
        XCTAssertGreaterThanOrEqual(score, config.tHigh)
    }

    func testBoostIsClampedToOne() {
        let target = UUID()
        var index = PrototypeIndex()
        index.setPrototype(proto([1, 0]), for: target)
        let scored = index.scored(for: [1, 0], boosts: [target: 5.0])
        XCTAssertEqual(scored.first?.score ?? 0, 1.0, accuracy: 1e-12)   // 1.0 + 5 clamped to 1
    }

    func testEmptyBoostsMatchesUnboostedPath() {
        var index = PrototypeIndex()
        index.setPrototype(proto([1, 0]), for: UUID())
        index.setPrototype(proto([0, 1]), for: UUID())
        let query: [Double] = [1, 1]
        XCTAssertEqual(
            index.decide(for: query, config: config),
            index.decide(for: query, config: config, boosts: [:])
        )
    }
}
