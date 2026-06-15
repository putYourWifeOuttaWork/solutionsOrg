import Foundation

/// UTF-8 text parser for `.txt` and `.md`.
///
/// `.md` is returned **raw** (no markdown stripping): Markdown structure is meaningful for
/// downstream embedding/retrieval, and raw UTF-8 text is the normalized form for it
/// (design note §6). A leading UTF-8 BOM is stripped; decoding is lenient (see
/// ``TextDecoding``).
public struct TextParser: DocumentParser {
    public init() {}

    public var supportedExtensions: [String] { ["txt", "md"] }

    public func parse(_ data: Data, filename: String) throws -> String {
        try TextDecoding.string(from: data, filename: filename)
    }
}
