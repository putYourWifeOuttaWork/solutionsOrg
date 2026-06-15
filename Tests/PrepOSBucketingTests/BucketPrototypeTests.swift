import XCTest
@testable import PrepOSBucketing

/// `BucketPrototype.score` and prototype learning (design note §4; PRD §8 step 3, C2.6).
final class BucketPrototypeTests: XCTestCase {

    private func vec(_ v: [Double]) -> LabeledVector {
        LabeledVector(label: UUID(), vector: v)
    }

    func testScoreIsMaxOverCentroidAndExemplars() {
        // Two orthogonal exemplars → centroid sits between them. A query equal to one
        // exemplar must score 1.0 (max over exemplars), not the lower centroid cosine.
        let e1: [Double] = [1, 0, 0, 0]
        let e2: [Double] = [0, 1, 0, 0]
        let proto = BucketPrototype(exemplars: [vec(e1), vec(e2)])
        let scoreToE1 = proto.score(e1)
        XCTAssertEqual(scoreToE1, 1.0, accuracy: 1e-12)
        // Centroid is normalized (e1+e2)/√2; cosine(centroid, e1) ≈ 0.707 < 1.
        XCTAssertGreaterThan(scoreToE1, cosineSimilarity(proto.centroid, e1) + 0.2)
    }

    func testSingleExemplarCentroidEqualsExemplarDirection() {
        let e: [Double] = [3, 4, 0]
        let proto = BucketPrototype(exemplars: [vec(e)])
        // Centroid is the L2-normalized exemplar → cosine to exemplar is 1.
        XCTAssertEqual(cosineSimilarity(proto.centroid, e), 1.0, accuracy: 1e-12)
        XCTAssertEqual(proto.score([6, 8, 0]), 1.0, accuracy: 1e-12)
    }

    func testOrthogonalQueryScoresZero() {
        let proto = BucketPrototype(exemplars: [vec([1, 0, 0]), vec([1, 0.2, 0])])
        XCTAssertEqual(proto.score([0, 0, 1]), 0.0, accuracy: 1e-12)
    }

    func testLearningShiftsCentroidTowardNewVector() {
        let e1: [Double] = [1, 0, 0, 0]
        let proto = BucketPrototype(exemplars: [vec(e1)])
        let newVec: [Double] = [0, 1, 0, 0]
        let learned = proto.learning(vec(newVec))
        let before = cosineSimilarity(proto.centroid, newVec)
        let after = cosineSimilarity(learned.centroid, newVec)
        XCTAssertGreaterThan(after, before, "centroid should move toward the new exemplar")
        XCTAssertEqual(learned.exemplars.count, 2)
    }

    func testLearningIsPureAndDoesNotMutateOriginal() {
        let proto = BucketPrototype(exemplars: [vec([1, 0, 0])])
        let originalCentroid = proto.centroid
        let originalCount = proto.exemplars.count
        _ = proto.learning(vec([0, 1, 0]))
        XCTAssertEqual(proto.centroid, originalCentroid)
        XCTAssertEqual(proto.exemplars.count, originalCount)
    }

    func testAddingExemplarEqualToCentroidLeavesCentroidUnchanged() {
        let proto = BucketPrototype(exemplars: [vec([1, 0, 0]), vec([0, 1, 0])])
        let learned = proto.learning(vec(proto.centroid))
        XCTAssertEqual(cosineSimilarity(learned.centroid, proto.centroid), 1.0, accuracy: 1e-9)
    }
}
