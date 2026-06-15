import Foundation

/// The local GRDB store: record types, migrations, AES-GCM encryption (key from SecretStore),
/// repositories, and encrypted export/backup (PRD §6, C8). Vector similarity is computed in
/// Swift for MVP; sqlite-vec is a later optimization.
///
/// Placeholder namespace — implemented in Phase 1 pieces P1-b/P1-g.
public enum PrepOSPersistence {}
