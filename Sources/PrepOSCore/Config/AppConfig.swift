import Foundation

/// User-adjustable tuning for the bucketing engine and prep pipeline (PRD §8, C2.8).
/// Defaults are the PRD's starting points; they are calibrated against real data in
/// Phase 1 acceptance. All values are user-adjustable in settings.
public struct AppConfig: Sendable, Codable, Equatable {
    /// Auto-file when the top match score is at least this (PRD §8 `T_high`).
    public var tHigh: Double
    /// Ambiguity floor — below this and far from all → propose a new bucket (`T_low`).
    public var tLow: Double
    /// Top-two within this margin → ambiguous even if above `T_low` (`T_margin`).
    public var tMargin: Double
    /// More than this many captures within a short window counts as a bulk operation (`N_bulk`).
    public var nBulk: Int
    /// How many hops prep traverses across bucket links (PRD C3.2).
    public var linkTraversalDepth: Int
    /// Calendar sync horizon in days (PRD C5.2).
    public var calendarHorizonDays: Int

    public init(
        tHigh: Double = 0.82,
        tLow: Double = 0.55,
        tMargin: Double = 0.07,
        nBulk: Int = 3,
        linkTraversalDepth: Int = 1,
        calendarHorizonDays: Int = 14
    ) {
        self.tHigh = tHigh
        self.tLow = tLow
        self.tMargin = tMargin
        self.nBulk = nBulk
        self.linkTraversalDepth = linkTraversalDepth
        self.calendarHorizonDays = calendarHorizonDays
    }

    /// The PRD §8 defaults.
    public static let `default` = AppConfig()
}
