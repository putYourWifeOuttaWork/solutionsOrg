import Foundation

/// Shared lenient text decoding for the plain-text and caption parsers.
///
/// Decoding is lenient where safe (design note §1): we try strict UTF-8 first, then fall back
/// to a lossy decode so a single stray byte in an otherwise-textual transcript does not hard-
/// fail the whole ingestion. A leading UTF-8 BOM is stripped so it never leaks into item text.
enum TextDecoding {
    /// Decode `data` to a `String`, stripping a leading UTF-8 BOM.
    ///
    /// A lossy UTF-8 decode replaces invalid sequences with U+FFFD rather than dropping
    /// content, so a stray byte in an otherwise-textual transcript never hard-fails ingestion.
    /// A strict decode is unnecessary: for valid UTF-8 it yields an identical string. `throws`
    /// and `filename` are retained for API symmetry with the binary parsers (PDF/DOCX).
    static func string(from data: Data, filename: String) throws -> String {
        String(decoding: stripBOM(data), as: UTF8.self)
    }

    /// Drop a leading UTF-8 byte-order mark (`EF BB BF`) if present.
    private static func stripBOM(_ data: Data) -> Data {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        if data.count >= 3, Array(data.prefix(3)) == bom {
            return data.subdata(in: data.startIndex.advanced(by: 3)..<data.endIndex)
        }
        return data
    }
}
