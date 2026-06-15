import XCTest
@testable import PrepOSCore

final class FilingDeciderTests: XCTestCase {
    let config = AppConfig.default   // tHigh 0.82, tLow 0.55, tMargin 0.07

    private func candidate(_ score: Double) -> ScoredBucket {
        ScoredBucket(bucketId: UUID(), score: score)
    }

    func testNoCandidatesProposesNewBucket() {
        XCTAssertEqual(FilingDecider.decide(candidates: [], config: config),
                       .proposeNewBucket(topScore: 0))
    }

    func testHighScoreClearWinnerAutoFiles() {
        let top = candidate(0.90)
        let decision = FilingDecider.decide(candidates: [top, candidate(0.40)], config: config)
        XCTAssertEqual(decision, .autoFile(bucketId: top.bucketId, score: 0.90))
    }

    func testSingleHighCandidateAutoFiles() {
        let top = candidate(0.83)
        XCTAssertEqual(FilingDecider.decide(candidates: [top], config: config),
                       .autoFile(bucketId: top.bucketId, score: 0.83))
    }

    func testHighScoreButCloseRunnerUpIsAmbiguous() {
        // Both above tHigh but within tMargin (0.07) → never silently misfile.
        let decision = FilingDecider.decide(candidates: [candidate(0.86), candidate(0.83)],
                                            config: config)
        guard case .ambiguous(let ranked) = decision else {
            return XCTFail("expected ambiguous, got \(decision)")
        }
        XCTAssertEqual(ranked.map(\.score), [0.86, 0.83])
    }

    func testMidScoreIsAmbiguous() {
        let decision = FilingDecider.decide(candidates: [candidate(0.60), candidate(0.30)],
                                            config: config)
        guard case .ambiguous = decision else {
            return XCTFail("expected ambiguous, got \(decision)")
        }
    }

    func testLowScoreProposesNewBucket() {
        let decision = FilingDecider.decide(candidates: [candidate(0.40), candidate(0.20)],
                                            config: config)
        XCTAssertEqual(decision, .proposeNewBucket(topScore: 0.40))
    }

    func testBoundaryAtTHighWithClearMarginAutoFiles() {
        let top = candidate(0.82)   // exactly tHigh
        XCTAssertEqual(FilingDecider.decide(candidates: [top, candidate(0.50)], config: config),
                       .autoFile(bucketId: top.bucketId, score: 0.82))
    }

    func testCandidatesAreRankedRegardlessOfInputOrder() {
        let best = candidate(0.95)
        let decision = FilingDecider.decide(candidates: [candidate(0.20), best, candidate(0.10)],
                                            config: config)
        XCTAssertEqual(decision, .autoFile(bucketId: best.bucketId, score: 0.95))
    }
}
