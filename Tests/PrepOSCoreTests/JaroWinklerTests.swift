import XCTest
@testable import PrepOSCore

final class JaroWinklerTests: XCTestCase {

    private func assertClose(_ a: Double, _ b: Double, _ msg: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, accuracy: 0.001, msg, file: file, line: line)
    }

    func testIdenticalStringsAreOne() {
        assertClose(JaroWinkler.similarity("Acme Corp", "Acme Corp"), 1.0)
    }

    func testDisjointStringsAreZero() {
        assertClose(JaroWinkler.similarity("abc", "xyz"), 0.0)
    }

    func testEmptyStrings() {
        assertClose(JaroWinkler.similarity("", ""), 1.0)
        assertClose(JaroWinkler.similarity("abc", ""), 0.0)
    }

    // Canonical Winkler reference values.
    func testMarthaMarhta() {
        assertClose(JaroWinkler.jaroSimilarity("MARTHA", "MARHTA"), 0.944, "jaro")
        assertClose(JaroWinkler.similarity("MARTHA", "MARHTA"), 0.961, "jaro-winkler")
    }

    func testDwayneDuane() {
        assertClose(JaroWinkler.jaroSimilarity("DWAYNE", "DUANE"), 0.822, "jaro")
        assertClose(JaroWinkler.similarity("DWAYNE", "DUANE"), 0.840, "jaro-winkler")
    }

    func testDixonDicksonh() {
        assertClose(JaroWinkler.jaroSimilarity("DIXON", "DICKSONX"), 0.767, "jaro")
        assertClose(JaroWinkler.similarity("DIXON", "DICKSONX"), 0.813, "jaro-winkler")
    }

    func testPrefixBoostRewardsCommonStart() {
        // Same Jaro, but the common prefix should lift the Winkler score.
        let withPrefix = JaroWinkler.similarity("Salesforce Inc", "Salesforce Incorporated")
        XCTAssertGreaterThan(withPrefix, 0.8)
        XCTAssertLessThanOrEqual(withPrefix, 1.0)
    }

    func testResultStaysInUnitRange() {
        for (a, b) in [("Acme", "Acme Corporation"), ("IBM", "International Business"),
                       ("a", "abcdefghij"), ("x", "x")] {
            let s = JaroWinkler.similarity(a, b)
            XCTAssert(s >= 0 && s <= 1, "\(a)/\(b) → \(s) out of range")
        }
    }
}
