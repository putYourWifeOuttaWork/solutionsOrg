import Foundation

/// The swappable AI backend abstraction (PRD §5.3). Every Claude call in PrepOS goes
/// through a `ReasoningProvider`, so the brain can be replaced (Claude today, a local
/// model later) without rewriting callers.
///
/// A provider owns: model selection, MCP server configuration, the `web_search` toggle,
/// token budgeting, and the context-disclosure record surfaced to the cockpit. It must
/// honor the read-only boundary via `ReadOnlyGuard` before dispatching anything.
public protocol ReasoningProvider: Sendable {
    /// Send a request to the backend and return its response.
    ///
    /// Implementations MUST call `ReadOnlyGuard.validate(servers:)` (and reject mutating
    /// tool dispatches) before contacting the network.
    func send(_ request: ReasoningRequest) async throws -> ReasoningResponse
}

/// Phase 0 stub (PRD T0.3). Performs no network I/O and does not reason. It still enforces
/// the read-only guard so tests can prove the boundary holds, and echoes the request's
/// disclosures back so the cockpit-transparency plumbing can be exercised end-to-end.
public struct NoOpReasoningProvider: ReasoningProvider {
    public init() {}

    public func send(_ request: ReasoningRequest) async throws -> ReasoningResponse {
        // Boundary first: a no-op must still refuse a write-capable configuration.
        try ReadOnlyGuard.validate(servers: request.mcpServers)

        return ReasoningResponse(
            text: "",
            toolInvocations: [],
            disclosures: request.disclosures,
            usage: ReasoningUsage()
        )
    }
}
