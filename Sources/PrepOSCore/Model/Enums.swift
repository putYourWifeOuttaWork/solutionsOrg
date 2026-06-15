import Foundation

// Domain enumerations (PRD §6). Raw `String` values so they persist stably and round-trip
// through Codable / GRDB without positional coupling.

/// What a bucket represents (PRD §6.1).
public enum BucketType: String, Sendable, Codable, CaseIterable, Equatable {
    case account
    case opportunity
    case project
    case topic
}

/// Lifecycle of a bucket (PRD §6.1).
public enum BucketStatus: String, Sendable, Codable, CaseIterable, Equatable {
    case active
    case archived
}

/// Kind of captured/derived item (PRD §6.2).
public enum ItemType: String, Sendable, Codable, CaseIterable, Equatable {
    case transcript
    case note
    case record
    case prepMaterial = "prep_material"
    case asset
}

/// How an item entered the system (PRD §6.2). `generated` = produced by the agent.
public enum CaptureMethod: String, Sendable, Codable, CaseIterable, Equatable {
    case dragdrop
    case paste
    case share
    case watchedFolder = "watched_folder"
    case hotkey
    case generated
}

/// Why two buckets are linked (PRD §6.3).
public enum BucketLinkRelation: String, Sendable, Codable, CaseIterable, Equatable {
    case accountOpportunity = "account_opportunity"
    case projectAccount = "project_account"
    case topicOverlap = "topic_overlap"
    case manual
}

/// Whether a link was inferred or user-made (PRD §6.3).
public enum LinkOrigin: String, Sendable, Codable, CaseIterable, Equatable {
    case auto
    case manual
}

/// Freshness of a prep brief (PRD §6.6).
public enum BriefStatus: String, Sendable, Codable, CaseIterable, Equatable {
    case fresh
    case stale
    case dismissed
}

/// Why an item landed in triage (PRD §6.7).
public enum TriageReason: String, Sendable, Codable, CaseIterable, Equatable {
    case lowConfidence = "low_confidence"
    case ambiguousTwoClose = "ambiguous_two_close"
    case noMatch = "no_match"
    case bulkDeferred = "bulk_deferred"
}

/// State of a triage item (PRD §6.7).
public enum TriageStatus: String, Sendable, Codable, CaseIterable, Equatable {
    case pending
    case resolved
}

/// Kind of generated asset (PRD §6.8).
public enum AssetKind: String, Sendable, Codable, CaseIterable, Equatable {
    case agenda
    case script
    case email
    case doc
    case deck
    case other
}

/// RSVP status for a calendar attendee (from Microsoft Graph; PRD §6.5).
public enum RSVPStatus: String, Sendable, Codable, CaseIterable, Equatable {
    case accepted
    case tentative
    case declined
    case none
    case organizer
}
