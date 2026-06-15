import XCTest
@testable import PrepOSParsing

/// Tests for the WebVTT caption parser (`.vtt`) with inline fixtures.
final class VTTParserTests: XCTestCase {
    private let parser = VTTParser()

    private func parse(_ vtt: String) throws -> String {
        try parser.parse(Data(vtt.utf8), filename: "clip.vtt")
    }

    func testSupportsVtt() {
        XCTAssertEqual(parser.supportedExtensions, ["vtt"])
    }

    func testStandardHeaderAndCuesYieldDialogueOnly() throws {
        let vtt = """
        WEBVTT

        00:00:01.000 --> 00:00:04.000
        Hello and welcome.

        00:00:04.000 --> 00:00:07.000
        Today we discuss the renewal.

        00:00:07.000 --> 00:00:10.000
        Let's get started.
        """
        let out = try parse(vtt)
        XCTAssertEqual(out, "Hello and welcome.\nToday we discuss the renewal.\nLet's get started.")
    }

    func testHeaderMetadataAndNoteBlockStripped() throws {
        let vtt = """
        WEBVTT
        Kind: captions
        Language: en

        NOTE
        This transcript was machine generated.

        00:00:01.000 --> 00:00:03.000
        Actual dialogue here.
        """
        let out = try parse(vtt)
        XCTAssertEqual(out, "Actual dialogue here.")
    }

    func testCueIdentifiersAndInlineTagsStripped() throws {
        let vtt = """
        WEBVTT

        intro-1
        00:00:01.000 --> 00:00:03.000
        <v Alex>Hi everyone</v>

        2
        00:00:03.000 --> 00:00:05.000
        <00:00:03.500>This <c>matters</c> a lot.
        """
        let out = try parse(vtt)
        XCTAssertEqual(out, "Hi everyone\nThis matters a lot.")
    }

    func testConsecutiveDuplicateLinesCollapse() throws {
        let vtt = """
        WEBVTT

        00:00:01.000 --> 00:00:02.000
        Rolling caption line

        00:00:02.000 --> 00:00:03.000
        Rolling caption line

        00:00:03.000 --> 00:00:04.000
        Rolling caption line
        Next line
        """
        let out = try parse(vtt)
        XCTAssertEqual(out, "Rolling caption line\nNext line")
    }

    func testMultiLineDialogueKeptUnderOneCue() throws {
        let vtt = """
        WEBVTT

        00:00:01.000 --> 00:00:05.000
        First spoken line
        Second spoken line
        """
        let out = try parse(vtt)
        XCTAssertEqual(out, "First spoken line\nSecond spoken line")
    }

    func testHeaderOnlyYieldsEmptyString() throws {
        XCTAssertEqual(try parse("WEBVTT\n\n"), "")
        XCTAssertEqual(try parse("WEBVTT"), "")
    }

    func testTimestampWithHoursStripped() throws {
        let vtt = """
        WEBVTT

        01:02:03.000 --> 01:02:05.000
        Late in the call.
        """
        let out = try parse(vtt)
        XCTAssertEqual(out, "Late in the call.")
    }
}
