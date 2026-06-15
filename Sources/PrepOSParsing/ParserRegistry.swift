import Foundation

/// Dispatches a captured file to the right ``DocumentParser`` by its (lowercased) extension.
///
/// This is the single entry point the ingestion pipeline uses to normalize a file into item
/// text before embedding (architecture.md §4). Built-in wiring is ``makeDefault()``.
public struct ParserRegistry: Sendable {
    private let parsersByExtension: [String: any DocumentParser]

    /// Build a registry from explicit parsers. A parser registers for each of its
    /// ``DocumentParser/supportedExtensions``; on conflict, **later parsers win**.
    public init(parsers: [any DocumentParser]) {
        var table: [String: any DocumentParser] = [:]
        for parser in parsers {
            for ext in parser.supportedExtensions {
                table[ext.lowercased()] = parser
            }
        }
        parsersByExtension = table
    }

    /// The default registry wiring all built-in parsers (txt/md/vtt/srt/pdf/docx).
    public static func makeDefault() -> ParserRegistry {
        ParserRegistry(parsers: [
            TextParser(),
            VTTParser(),
            SRTParser(),
            PDFParser(),
            DocxParser()
        ])
    }

    /// Returns the parser registered for `ext` (lowercased, no dot), or `nil`.
    public func parser(forExtension ext: String) -> (any DocumentParser)? {
        parsersByExtension[ext.lowercased()]
    }

    /// Returns the parser for `filename`'s extension, or `nil` if none is registered (or the
    /// filename has no extension).
    public func parser(forFilename filename: String) -> (any DocumentParser)? {
        guard let ext = Self.fileExtension(of: filename) else { return nil }
        return parser(forExtension: ext)
    }

    /// Dispatch and parse `data` for `filename` by extension.
    /// - Throws: ``ParsingError/missingExtension`` when the filename has no extension,
    ///   ``ParsingError/unsupportedExtension(_:)`` when no parser is registered for it, or
    ///   the chosen parser's own error.
    public func parse(_ data: Data, filename: String) throws -> String {
        guard let ext = Self.fileExtension(of: filename) else {
            throw ParsingError.missingExtension
        }
        guard let parser = parser(forExtension: ext) else {
            throw ParsingError.unsupportedExtension(ext)
        }
        return try parser.parse(data, filename: filename)
    }

    /// The lowercased extension after the **last** dot (so `q3.deal.notes.md` → `md`), or
    /// `nil` when there is no non-empty extension segment.
    private static func fileExtension(of filename: String) -> String? {
        let name = (filename as NSString).lastPathComponent
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
        let ext = name[name.index(after: dot)...]
        return ext.isEmpty ? nil : ext.lowercased()
    }
}
