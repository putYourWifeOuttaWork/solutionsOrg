import Foundation

/// A parser that turns a captured file's bytes into normalized plain item text (PRD C1.5).
///
/// Implementations are pure/stateless and `Sendable`; platform-backed parsers (PDF/DOCX)
/// hide their framework behind this protocol so the ingestion pipeline
/// (`capture surface → normalize text (parser) → EmbeddingService.embed`,
/// architecture.md §4) stays testable without Xcode-only frameworks.
public protocol DocumentParser: Sendable {
    /// File extensions this parser handles, lowercased, without the leading dot
    /// (e.g. `["txt", "md"]`). Used by ``ParserRegistry`` for dispatch.
    var supportedExtensions: [String] { get }

    /// Decode `data` (a file named `filename`) into normalized plain text.
    /// - Throws: ``ParsingError`` on decode/format failure or unavailable platform support.
    func parse(_ data: Data, filename: String) throws -> String
}

/// Errors surfaced by the parsing layer.
public enum ParsingError: Error, Sendable, Equatable {
    /// No registered parser handles the file's extension.
    case unsupportedExtension(String)
    /// The filename had no usable extension to dispatch on.
    case missingExtension
    /// The bytes could not be decoded as text in the expected encoding.
    case decodingFailed(filename: String)
    /// The format was structurally invalid (e.g. unreadable PDF/DOCX container).
    case malformedDocument(filename: String, detail: String)
    /// The parser needs a platform framework (PDFKit/AppKit) not available in this build.
    case platformUnavailable(format: String)
}
