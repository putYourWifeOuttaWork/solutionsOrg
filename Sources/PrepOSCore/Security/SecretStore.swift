import Foundation

/// Abstraction over secret storage (Security Constitution §1). The app target implements
/// this with the macOS **Keychain** (device-only accessibility); tests use an in-memory
/// fake. Package code depends only on this protocol and never touches the Keychain
/// directly, so logic stays testable and secrets never leak into source, logs, or config.
///
/// This is a **frozen shared contract** — persistence (for the AES-GCM database key),
/// reasoning (for the Anthropic API key), and integrations (for Graph tokens) all depend
/// on it. Change it deliberately.
public protocol SecretStore: Sendable {
    /// Return the secret bytes for `key`, or `nil` if absent.
    func data(for key: SecretKey) throws -> Data?

    /// Store `data` for `key`, replacing any existing value.
    func set(_ data: Data, for key: SecretKey) throws

    /// Remove the secret for `key` if present.
    func remove(_ key: SecretKey) throws
}

/// A stable identifier for a stored secret. Raw values are the Keychain account names.
public struct SecretKey: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    /// AES-GCM data-protection key for the local database (Constitution §2).
    public static let databaseKey = SecretKey("database.aesgcm.key")
    /// Anthropic Claude API key (Constitution §1).
    public static let anthropicAPIKey = SecretKey("anthropic.api.key")
    /// Microsoft Graph OAuth token bundle (Constitution §1).
    public static let graphTokens = SecretKey("microsoft.graph.tokens")
}

public extension SecretStore {
    /// Convenience: fetch a UTF-8 string secret.
    func string(for key: SecretKey) throws -> String? {
        try data(for: key).flatMap { String(data: $0, encoding: .utf8) }
    }
    /// Convenience: store a UTF-8 string secret.
    func set(_ string: String, for key: SecretKey) throws {
        try set(Data(string.utf8), for: key)
    }
}
