import Foundation

/// Top-level namespace + build metadata for PrepOS.
///
/// `PrepOSCore` holds the dependency-free heart of PrepOS: the domain model (PRD §6),
/// configuration, and pure algorithms (the filing decision rule and Jaro-Winkler). It is
/// deliberately free of app-only frameworks and I/O so it builds and tests under Command
/// Line Tools (see CLAUDE.md §4). Higher targets — Persistence, Reasoning, Bucketing —
/// build on it.
public enum PrepOS {
    /// Semantic version of the kit. Bump as phases land.
    public static let version = "0.0.1"

    /// Minimum supported macOS version (PRD §5.1).
    public static let minimumMacOS = "14.0"
}
