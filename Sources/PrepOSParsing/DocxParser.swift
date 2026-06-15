import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// DOCX (Office Open XML) text extractor backed by `NSAttributedString`'s `.officeOpenXML`
/// reader, returning its plain `.string`.
///
/// The reader lives in AppKit on macOS, so it is gated behind `#if canImport(AppKit)`: on a
/// toolchain lacking it, ``parse(_:filename:)`` throws
/// ``ParsingError/platformUnavailable(format:)``. Malformed/unreadable containers throw
/// ``ParsingError/malformedDocument(filename:detail:)`` (design note §3).
public struct DocxParser: DocumentParser {
    public init() {}

    public var supportedExtensions: [String] { ["docx"] }

    public func parse(_ data: Data, filename: String) throws -> String {
        #if canImport(AppKit)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.officeOpenXML
        ]
        do {
            let attributed = try NSAttributedString(data: data, options: options, documentAttributes: nil)
            return attributed.string
        } catch {
            throw ParsingError.malformedDocument(
                filename: filename,
                detail: "NSAttributedString could not read the data as Office Open XML: \(error.localizedDescription)"
            )
        }
        #else
        throw ParsingError.platformUnavailable(format: "docx")
        #endif
    }
}
