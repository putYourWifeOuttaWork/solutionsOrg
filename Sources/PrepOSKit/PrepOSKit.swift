import Foundation

/// Top-level namespace + build metadata for PrepOS.
///
/// PrepOSKit holds the testable core of PrepOS: domain model, the `ReasoningProvider`
/// abstraction, bucketing, parsing, and retrieval. It is deliberately free of app-only
/// frameworks so it builds and tests under Command Line Tools (see CLAUDE.md §4).
public enum PrepOS {
    /// Semantic version of the kit. Bump as phases land.
    public static let version = "0.0.1"

    /// Minimum supported macOS version (PRD §5.1).
    public static let minimumMacOS = "14.0"
}
