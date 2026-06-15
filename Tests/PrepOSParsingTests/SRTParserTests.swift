import XCTest
@testable import PrepOSParsing

/// Tests for the SubRip caption parser (`.srt`) with inline fixtures.
final class SRTParserTests: XCTestCase {
    private let parser = SRTParser()

    private func parse(_ srt: String) throws -> String {
        try parser.parse(Data(srt.utf8), filename: "clip.srt")
    }

    func testSupportsSrt() {
        XCTAssertEqual(parser.supportedExtensions, ["srt"])
    }

    func testStandardBlocksYieldDialogueOnly() throws {
        let srt = """
        1
        00:00:01,000 --> 00:00:04,000
        Hello and welcome.

        2
        00:00:04,000 --> 00:00:07,000
        Today we discuss the renewal.
        """
        let out = try parse(srt)
        XCTAssertEqual(out, "Hello and welcome.\nToday we discuss the renewal.")
    }

    func testCommaMillisecondTimestampsStripped() throws {
        let srt = """
        1
        00:00:01,500 --> 00:00:03,250
        Comma millis.
        """
        let out = try parse(srt)
        XCTAssertEqual(out, "Comma millis.")
    }

    func testTrailingBlankLinesTolerated() throws {
        let srt = "1\n00:00:01,000 --> 00:00:02,000\nOnly line.\n\n\n"
        let out = try parse(srt)
        XCTAssertEqual(out, "Only line.")
    }

    func testConsecutiveDuplicatesDeduplicated() throws {
        let srt = """
        1
        00:00:01,000 --> 00:00:02,000
        Same line

        2
        00:00:02,000 --> 00:00:03,000
        Same line
        """
        let out = try parse(srt)
        XCTAssertEqual(out, "Same line")
    }

    func testSingleCueNoTrailingNewline() throws {
        let srt = "1\n00:00:01,000 --> 00:00:04,000\nNo trailing newline."
        let out = try parse(srt)
        XCTAssertEqual(out, "No trailing newline.")
    }

    func testEmptyInputYieldsEmptyString() throws {
        XCTAssertEqual(try parse(""), "")
    }
}
