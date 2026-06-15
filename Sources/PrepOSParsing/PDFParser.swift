import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// PDF text extractor (`.pdf`) backed by **PDFKit**; the text of all pages is joined by `\n`.
///
/// PDFKit is gated behind `#if canImport(PDFKit)` so the package still compiles on a toolchain
/// lacking it — in that case ``parse(_:filename:)`` throws
/// ``ParsingError/platformUnavailable(format:)`` at runtime (design note §3).
public struct PDFParser: DocumentParser {
    public init() {}

    public var supportedExtensions: [String] { ["pdf"] }

    public func parse(_ data: Data, filename: String) throws -> String {
        #if canImport(PDFKit)
        guard let document = PDFDocument(data: data) else {
            throw ParsingError.malformedDocument(
                filename: filename,
                detail: "PDFKit could not open the data as a PDF document."
            )
        }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            if let text = document.page(at: index)?.string {
                pages.append(text)
            }
        }
        return pages.joined(separator: "\n")
        #else
        throw ParsingError.platformUnavailable(format: "pdf")
        #endif
    }
}
