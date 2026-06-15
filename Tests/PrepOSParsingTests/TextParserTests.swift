import XCTest
@testable import PrepOSParsing

/// Exhaustive tests for the pure UTF-8 `TextParser` (`.txt`, `.md`) using inline
/// `Data(string.utf8)` fixtures — no fixture files.
final class TextParserTests: XCTestCase {
    private let parser = TextParser()

    func testSupportsTxtAndMd() {
        XCTAssertEqual(parser.supportedExtensions, ["txt", "md"])
    }

    func testTxtDecodesToIdenticalText() throws {
        let text = "Hello, deal notes.\nLine two."
        let out = try parser.parse(Data(text.utf8), filename: "notes.txt")
        XCTAssertEqual(out, text)
    }

    func testMarkdownReturnedRaw() throws {
        let md = "# Heading\n\nSome **bold** and a [link](https://example.com).\n- bullet"
        let out = try parser.parse(Data(md.utf8), filename: "notes.md")
        XCTAssertEqual(out, md, "Markdown markers must be preserved verbatim")
    }

    func testEmptyFileYieldsEmptyString() throws {
        let out = try parser.parse(Data(), filename: "empty.txt")
        XCTAssertEqual(out, "")
    }

    func testMultiByteUTF8RoundTrips() throws {
        let text = "café — naïve 🚀 résumé"
        let out = try parser.parse(Data(text.utf8), filename: "uni.txt")
        XCTAssertEqual(out, text)
    }

    func testUTF8BOMIsStripped() throws {
        var bytes = Data([0xEF, 0xBB, 0xBF])   // UTF-8 BOM
        bytes.append(Data("content".utf8))
        let out = try parser.parse(bytes, filename: "bom.txt")
        XCTAssertEqual(out, "content", "BOM must not leak into the decoded text")
    }
}
