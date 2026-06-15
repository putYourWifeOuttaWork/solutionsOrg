import XCTest
@testable import PrepOSKit

final class ReasoningProviderTests: XCTestCase {

    func testNoOpReturnsEmptyTextAndEchoesDisclosures() async throws {
        let provider = NoOpReasoningProvider()
        let disclosures = [
            ContextDisclosure(kind: .localItem, label: "Acme call notes", approximateTokens: 120)
        ]
        let request = ReasoningRequest(
            messages: [ReasoningMessage(role: .user, text: "Prep me for Acme.")],
            disclosures: disclosures
        )

        let response = try await provider.send(request)

        XCTAssertEqual(response.text, "")
        XCTAssertEqual(response.disclosures, disclosures)
        XCTAssertTrue(response.toolInvocations.isEmpty)
    }

    func testModelIdsResolveToLatestClaudeModels() {
        XCTAssertEqual(ReasoningModel.sonnet.apiModelId, "claude-sonnet-4-6")
        XCTAssertEqual(ReasoningModel.opus.apiModelId, "claude-opus-4-8")
    }

    func testDefaultRequestUsesSonnetAndNoWebSearch() {
        let request = ReasoningRequest(messages: [ReasoningMessage(role: .user, text: "hi")])
        XCTAssertEqual(request.model, .sonnet)
        XCTAssertFalse(request.enableWebSearch)
        XCTAssertTrue(request.mcpServers.isEmpty)
    }
}

final class ReadOnlyGuardTests: XCTestCase {

    func testWriteConnectorHostIsRejected() {
        let writeServer = MCPServerConfig(
            name: "Altify Write",
            url: URL(string: "https://write.mcp.altify.dev/mcp")!
        )
        XCTAssertThrowsError(try ReadOnlyGuard.validate(servers: [writeServer])) { error in
            XCTAssertEqual(error as? ReasoningError, .writeToolForbidden(toolOrServer: "Altify Write"))
        }
    }

    func testReadConnectorsAreAllowed() throws {
        let readServers = [
            MCPServerConfig(name: "Altify Salesforce",
                            url: URL(string: "https://salesforce.mcp.altify.dev/mcp")!),
            MCPServerConfig(name: "Altify Retrieve",
                            url: URL(string: "https://retrieve.mcp.altify.dev/mcp")!),
            MCPServerConfig(name: "Altify Analysis",
                            url: URL(string: "https://analysis.mcp.altify.dev/mcp")!)
        ]
        XCTAssertNoThrow(try ReadOnlyGuard.validate(servers: readServers))
    }

    func testMutatingToolNamesAreForbidden() {
        for name in ["altify_upsert_opp_salesprocess",
                     "altify_create_opp_insightcardcontact",
                     "altify_update_account",
                     "delete_event"] {
            XCTAssertTrue(ReadOnlyGuard.isForbiddenToolName(name), "\(name) should be forbidden")
            XCTAssertThrowsError(try ReadOnlyGuard.validateToolName(name))
        }
    }

    func testReadToolNamesAreAllowed() {
        for name in ["altify_find_acc",
                     "altify_find_opp",
                     "altify_read_opp_salesprocess",
                     "altify_get_acc_assessment"] {
            XCTAssertFalse(ReadOnlyGuard.isForbiddenToolName(name), "\(name) should be allowed")
            XCTAssertNoThrow(try ReadOnlyGuard.validateToolName(name))
        }
    }

    func testNoOpProviderEnforcesGuard() async {
        let provider = NoOpReasoningProvider()
        let request = ReasoningRequest(
            messages: [ReasoningMessage(role: .user, text: "go")],
            mcpServers: [MCPServerConfig(name: "Altify Write",
                                         url: URL(string: "https://write.mcp.altify.dev/mcp")!)]
        )
        do {
            _ = try await provider.send(request)
            XCTFail("Expected the no-op provider to reject a write-capable server")
        } catch {
            XCTAssertEqual(error as? ReasoningError, .writeToolForbidden(toolOrServer: "Altify Write"))
        }
    }
}
