import Foundation

// Types that flow through the `ReasoningProvider`. These model the *intent* of a Claude
// Messages API call (PRD §11) without binding to any transport, so the backend stays
// swappable (Claude today, a local model later) and the core stays testable.

/// Which model tier to use. Routine work uses Sonnet; heavy synthesis uses Opus (PRD §5.1).
public enum ReasoningModel: String, Sendable, Codable, CaseIterable {
    case sonnet
    case opus

    /// Concrete model id sent to the API. Centralized here so routing policy lives in one place.
    public var apiModelId: String {
        switch self {
        case .sonnet: return "claude-sonnet-4-6"
        case .opus: return "claude-opus-4-8"
        }
    }
}

/// A chat role in a reasoning exchange.
public enum ReasoningRole: String, Sendable, Codable {
    case user
    case assistant
}

/// One message in the conversation sent to the model.
public struct ReasoningMessage: Sendable, Codable, Equatable {
    public var role: ReasoningRole
    public var text: String

    public init(role: ReasoningRole, text: String) {
        self.role = role
        self.text = text
    }
}

/// An MCP server made available to the model. PrepOS only ever wires **read** servers
/// (PRD Appendix A). The Write connector is architecturally absent — see `ReadOnlyGuard`.
public struct MCPServerConfig: Sendable, Codable, Equatable {
    public var name: String
    public var url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}

/// A single piece of context being sent to the cloud, recorded for the cockpit's
/// "what is leaving the device" disclosure (PRD §7 C7.5, §12).
public struct ContextDisclosure: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable {
        case localItem        // a user transcript/note/doc chunk
        case altifyRecord     // a Salesforce/Altify object read via MCP
        case webSource        // a web_search result
        case systemPrompt     // instructions
    }

    public var kind: Kind
    public var label: String          // human-readable ("Acme Q3 transcript", "Opp 006…")
    public var approximateTokens: Int

    public init(kind: Kind, label: String, approximateTokens: Int) {
        self.kind = kind
        self.label = label
        self.approximateTokens = approximateTokens
    }
}

/// A request to the reasoning backend. Owns model selection, MCP config, web_search
/// toggle, token budget, and the disclosure record (PRD §5.3).
public struct ReasoningRequest: Sendable {
    public var model: ReasoningModel
    public var system: String?
    public var messages: [ReasoningMessage]
    public var mcpServers: [MCPServerConfig]
    public var enableWebSearch: Bool
    public var maxTokens: Int
    /// What this request will send to the cloud, for cockpit transparency.
    public var disclosures: [ContextDisclosure]

    public init(
        model: ReasoningModel = .sonnet,
        system: String? = nil,
        messages: [ReasoningMessage],
        mcpServers: [MCPServerConfig] = [],
        enableWebSearch: Bool = false,
        maxTokens: Int = 4096,
        disclosures: [ContextDisclosure] = []
    ) {
        self.model = model
        self.system = system
        self.messages = messages
        self.mcpServers = mcpServers
        self.enableWebSearch = enableWebSearch
        self.maxTokens = maxTokens
        self.disclosures = disclosures
    }
}

/// Provenance for a single tool invocation the model made (PRD §11: capture every
/// `mcp_tool_use` + web source). Recorded by `type`, never by position.
public struct ToolInvocationRecord: Sendable, Codable, Equatable {
    public enum Source: String, Sendable, Codable {
        case mcp
        case webSearch
    }

    public var source: Source
    public var serverName: String?   // for MCP
    public var toolName: String
    public var summary: String       // high-level inputs, not raw payloads

    public init(source: Source, serverName: String? = nil, toolName: String, summary: String) {
        self.source = source
        self.serverName = serverName
        self.toolName = toolName
        self.summary = summary
    }
}

/// Token accounting returned by the backend, for budgeting (PRD §5.3).
public struct ReasoningUsage: Sendable, Codable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int

    public init(inputTokens: Int = 0, outputTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

/// The backend's response. `text` is the assembled assistant output; `toolInvocations`
/// and `disclosures` feed the cockpit's provenance view.
public struct ReasoningResponse: Sendable {
    public var text: String
    public var toolInvocations: [ToolInvocationRecord]
    public var disclosures: [ContextDisclosure]
    public var usage: ReasoningUsage

    public init(
        text: String,
        toolInvocations: [ToolInvocationRecord] = [],
        disclosures: [ContextDisclosure] = [],
        usage: ReasoningUsage = ReasoningUsage()
    ) {
        self.text = text
        self.toolInvocations = toolInvocations
        self.disclosures = disclosures
        self.usage = usage
    }
}

/// Errors surfaced by the reasoning layer.
public enum ReasoningError: Error, Sendable, Equatable {
    /// A tool or MCP server matched a forbidden write/mutation pattern (PRD §11, §12).
    case writeToolForbidden(toolOrServer: String)
    /// The backend is a stub and cannot actually reason (no-op provider).
    case notImplemented
    /// Transport/backend failure with a message.
    case backend(String)
}
