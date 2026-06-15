import XCTest
@testable import PrepOSPersistence

/// Constitution boundary (CLAUDE.md §1; security constitution §1, §3–4): this target is
/// local disk I/O only. A source-text assertion (mirroring the boundary tests in other
/// targets) that `Sources/PrepOSPersistence/` imports no networking / Altify / Graph symbol
/// and references no write-MCP host; secret access is exclusively through `SecretStore`.
final class ConstitutionBoundaryTests: XCTestCase {

    /// Resolve the target's source directory from this test file's location.
    private func sourceFiles() throws -> [URL] {
        let here = URL(fileURLWithPath: #filePath)             // …/Tests/PrepOSPersistenceTests/this.swift
        let repoRoot = here
            .deletingLastPathComponent()   // PrepOSPersistenceTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let srcDir = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("PrepOSPersistence")
        let urls = try FileManager.default.subpathsOfDirectory(atPath: srcDir.path)
            .filter { $0.hasSuffix(".swift") }
            .map { srcDir.appendingPathComponent($0) }
        XCTAssertFalse(urls.isEmpty, "no source files found at \(srcDir.path)")
        return urls
    }

    func testNoNetworkOrWriteAffordanceInSource() throws {
        // Symbols that would indicate a network stack, a Salesforce/Altify write surface, or
        // a direct Keychain reach-around. None may appear anywhere in this target's source.
        // Network / write / Keychain *symbols* — not prose. ("Graph" as a word appears in
        // doc-comments describing the origin of a calendar event id, so we match the actual
        // Graph/MSAL import surface instead.)
        let forbidden = [
            "URLSession", "URLRequest", "import Network",
            "https://write.mcp.altify.dev",
            "altify_upsert", "altify_create", "altify_update", "altify_delete",
            "import MSAL", "MicrosoftGraph", "graph.microsoft.com",
            "SecItemAdd", "SecItemCopyMatching", "kSecClass",
        ]
        for url in try sourceFiles() {
            let text = try String(contentsOf: url, encoding: .utf8)
            for symbol in forbidden {
                XCTAssertFalse(
                    text.contains(symbol),
                    "forbidden symbol \"\(symbol)\" found in \(url.lastPathComponent)"
                )
            }
        }
    }

    func testSecretsFlowOnlyThroughSecretStore() throws {
        // The only secret access is via the SecretStore protocol (SecretKey.databaseKey).
        // Assert the source references SecretStore and never an env var / UserDefaults / file
        // path for key material.
        let leaks = ["UserDefaults", "ProcessInfo.processInfo.environment", "getenv"]
        var sawSecretStore = false
        for url in try sourceFiles() {
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("SecretStore") { sawSecretStore = true }
            for leak in leaks {
                XCTAssertFalse(text.contains(leak),
                               "secret-leak channel \"\(leak)\" in \(url.lastPathComponent)")
            }
        }
        XCTAssertTrue(sawSecretStore, "expected SecretStore usage in persistence source")
    }
}
