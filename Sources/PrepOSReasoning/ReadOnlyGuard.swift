import Foundation

/// Enforcement layer #2 of the read-only boundary (PRD §11, §12): the provider rejects any
/// tool name or MCP server that matches a write/mutation pattern before dispatch.
///
/// Layer #1 is configuration (the Write connector URL is never present). Layer #3 is the
/// cockpit's record of every record touched. This guard is the runtime backstop: even if a
/// write-capable server were somehow configured, requests routing it are refused.
public enum ReadOnlyGuard {
    /// The forbidden Altify Write connector host (PRD Appendix A) — must never be wired.
    static let forbiddenServerHosts: Set<String> = [
        "write.mcp.altify.dev"
    ]

    /// Case-insensitive substrings that mark a tool as mutating. Matched against tool names
    /// like `altify_upsert_opp_*`, `altify_create_opp_*`, etc.
    static let mutationTokens: [String] = [
        "write", "upsert", "create", "update", "delete", "insert", "set_", "modify", "remove"
    ]

    /// Throws `ReasoningError.writeToolForbidden` if any configured MCP server is a known
    /// write host. Call this before sending a request.
    public static func validate(servers: [MCPServerConfig]) throws {
        for server in servers {
            if let host = server.url.host, forbiddenServerHosts.contains(host.lowercased()) {
                throw ReasoningError.writeToolForbidden(toolOrServer: server.name)
            }
        }
    }

    /// Returns `true` if a tool name looks like a mutation and must not be invoked.
    public static func isForbiddenToolName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return mutationTokens.contains { lowered.contains($0) }
    }

    /// Throws if the named tool is a mutation. Call before honoring any tool dispatch.
    public static func validateToolName(_ name: String) throws {
        if isForbiddenToolName(name) {
            throw ReasoningError.writeToolForbidden(toolOrServer: name)
        }
    }
}
