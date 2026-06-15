import XCTest
@testable import PrepOSBucketing

/// Pure `cosineSimilarity` over `[Double]` (design note §4).
final class CosineSimilarityTests: XCTestCase {

    func testIdenticalVectorsAreOne() {
        let v = [1.0, 2.0, 3.0, 4.0]
        XCTAssertEqual(cosineSimilarity(v, v), 1.0, accuracy: 1e-12)
    }

    func testAntiparallelVectorsAreMinusOne() {
        let a = [1.0, 2.0, 3.0]
        let b = a.map { -$0 }
        XCTAssertEqual(cosineSimilarity(a, b), -1.0, accuracy: 1e-12)
    }

    func testOrthogonalVectorsAreZero() {
        XCTAssertEqual(cosineSimilarity([1.0, 0.0], [0.0, 1.0]), 0.0, accuracy: 1e-12)
    }

    func testZeroVectorGivesZeroNotNaN() {
        let result = cosineSimilarity([0.0, 0.0, 0.0], [1.0, 2.0, 3.0])
        XCTAssertFalse(result.isNaN)
        XCTAssertEqual(result, 0.0)
    }

    func testScaleInvariance() {
        let a = [0.3, 0.4, 0.5]
        let scaled = a.map { $0 * 7.5 }
        XCTAssertEqual(cosineSimilarity(a, scaled), 1.0, accuracy: 1e-12)
    }
}
