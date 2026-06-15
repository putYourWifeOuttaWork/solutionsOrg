import XCTest
@testable import PrepOSParsing

/// Constitution boundary test (Security Constitution §3, §4): the parsing layer is a pure
/// local byte→text transform with **no** network and **no** Salesforce/Altify write surface.
/// Mirrors the grep-style boundary tests in testing-strategy.md §3 by scanning the target's
/// own source tree (resolved via `#filePath`) for forbidden tokens.
final class ConstitutionBoundaryTests: XCTestCase {

    func testNoNetworkOrWriteSymbolsInParsingSources() throws {
        let sourcesDir = Self.sourcesDirectory()
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: sourcesDir, includingPropertiesForKeys: nil) else {
            return XCTFail("could not enumerate \(sourcesDir.path)")
        }

        // Forbidden substrings: network clients and any Altify/SFDC write surface.
        let forbidden = ["URLSession", "write.mcp.altify.dev", "altify_", "upsert", "Mail.Send"]

        var scanned = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let contents = try String(contentsOf: url, encoding: .utf8)
            scanned += 1
            for token in forbidden {
                XCTAssertFalse(
                    contents.contains(token),
                    "Forbidden token '\(token)' found in \(url.lastPathComponent)"
                )
            }
        }
        XCTAssertGreaterThan(scanned, 0, "expected to scan at least one source file")
    }

    /// Resolve `Sources/PrepOSParsing/` from this test file's location (Tests/PrepOSParsingTests/).
    private static func sourcesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)            // .../Tests/PrepOSParsingTests/ConstitutionBoundaryTests.swift
            .deletingLastPathComponent()           // .../Tests/PrepOSParsingTests
            .deletingLastPathComponent()           // .../Tests
            .deletingLastPathComponent()           // package root
            .appendingPathComponent("Sources/PrepOSParsing", isDirectory: true)
    }
}
