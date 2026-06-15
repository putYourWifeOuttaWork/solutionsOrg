import XCTest
#if canImport(PDFKit)
import PDFKit
#endif
@testable import PrepOSParsing

/// PDF/DOCX smoke + negative-path tests.
///
/// **Approach / limitation:** Constructing a valid `.docx` (zipped OOXML) container in-memory
/// without a real fixture file is impractical, so DOCX coverage here is the negative path
/// (malformed bytes must throw, never silently return garbage); real `.docx` extraction is
/// verified manually and by the App target's integration pass. For PDF, when PDFKit is
/// available we synthesize a one-page PDF in-memory via `PDFDocument` and assert the known
/// text round-trips; the negative path (non-PDF bytes) is asserted unconditionally.
final class BinaryParserTests: XCTestCase {

    func testPDFParserSupportsPdf() {
        XCTAssertEqual(PDFParser().supportedExtensions, ["pdf"])
    }

    func testDocxParserSupportsDocx() {
        XCTAssertEqual(DocxParser().supportedExtensions, ["docx"])
    }

    func testPDFRoundTripsKnownText() throws {
        #if canImport(PDFKit)
        let known = "Quarterly renewal summary"
        guard let pdfData = Self.makeSinglePagePDF(text: known) else {
            throw XCTSkip("Could not synthesize a PDF fixture in this environment.")
        }
        let out = try PDFParser().parse(pdfData, filename: "doc.pdf")
        XCTAssertTrue(out.contains(known), "extracted text should contain the embedded string; got: \(out)")
        #else
        throw XCTSkip("PDFKit unavailable on this platform.")
        #endif
    }

    func testNonPDFBytesThrow() {
        XCTAssertThrowsError(try PDFParser().parse(Data("not a pdf".utf8), filename: "x.pdf"))
    }

    func testNonDocxBytesThrowMalformed() {
        XCTAssertThrowsError(try DocxParser().parse(Data("not a docx".utf8), filename: "x.docx")) { error in
            switch error as? ParsingError {
            case .malformedDocument, .platformUnavailable:
                break  // both acceptable: malformed input, or platform reader absent
            default:
                XCTFail("expected .malformedDocument or .platformUnavailable, got \(error)")
            }
        }
    }

    #if canImport(PDFKit)
    /// Synthesize a single-page PDF containing `text` by drawing into a PDF graphics context.
    private static func makeSinglePagePDF(text: String) -> Data? {
        let pageRect = CGRect(x: 0, y: 0, width: 200, height: 200)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = pageRect
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        ctx.beginPDFPage(nil)
        let attr = NSAttributedString(string: text)
        let line = CTLineCreateWithAttributedString(attr)
        ctx.textPosition = CGPoint(x: 10, y: 100)
        CTLineDraw(line, ctx)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }
    #endif
}
