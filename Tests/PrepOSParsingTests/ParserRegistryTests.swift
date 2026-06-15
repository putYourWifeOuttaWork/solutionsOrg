import XCTest
@testable import PrepOSParsing

/// Tests for `ParserRegistry` dispatch by file extension.
final class ParserRegistryTests: XCTestCase {
    private let registry = ParserRegistry.makeDefault()

    func testDispatchesByExtension() throws {
        XCTAssertEqual(
            try registry.parse(Data("plain".utf8), filename: "report.txt"),
            "plain"
        )
        let vtt = "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nVtt line."
        XCTAssertEqual(try registry.parse(Data(vtt.utf8), filename: "a.vtt"), "Vtt line.")
        let srt = "1\n00:00:01,000 --> 00:00:02,000\nSrt line."
        XCTAssertEqual(try registry.parse(Data(srt.utf8), filename: "b.srt"), "Srt line.")
    }

    func testExtensionMatchingIsCaseInsensitive() throws {
        XCTAssertNotNil(registry.parser(forFilename: "NOTES.MD"))
        XCTAssertNotNil(registry.parser(forFilename: "Clip.VTT"))
        XCTAssertEqual(try registry.parse(Data("# H".utf8), filename: "NOTES.MD"), "# H")
    }

    func testMultiDotFilenameUsesLastSegment() throws {
        let out = try registry.parse(Data("# q3".utf8), filename: "q3.deal.notes.md")
        XCTAssertEqual(out, "# q3")
    }

    func testUnknownExtensionThrows() {
        XCTAssertThrowsError(try registry.parse(Data(), filename: "data.xyz")) { error in
            XCTAssertEqual(error as? ParsingError, .unsupportedExtension("xyz"))
        }
    }

    func testMissingExtensionThrows() {
        XCTAssertThrowsError(try registry.parse(Data(), filename: "README")) { error in
            XCTAssertEqual(error as? ParsingError, .missingExtension)
        }
    }

    func testMakeDefaultResolvesAllBuiltInFormats() {
        for ext in ["txt", "md", "vtt", "srt", "pdf", "docx"] {
            XCTAssertNotNil(
                registry.parser(forExtension: ext),
                "default registry should resolve a parser for .\(ext)"
            )
        }
    }

    func testLaterParsersWinOnConflict() throws {
        struct StubParser: DocumentParser {
            let supportedExtensions = ["txt"]
            let marker: String
            func parse(_ data: Data, filename: String) throws -> String { marker }
        }
        let custom = ParserRegistry(parsers: [
            StubParser(marker: "first"),
            StubParser(marker: "second")
        ])
        XCTAssertEqual(try custom.parse(Data(), filename: "x.txt"), "second")
    }
}
