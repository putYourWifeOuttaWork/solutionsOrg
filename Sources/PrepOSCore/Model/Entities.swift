import Foundation

// The PrepOS domain entities (PRD §6) as pure value types. Each is `Sendable`, `Codable`,
// and `Identifiable`. Persistence conformance (GRDB) is added in PrepOSPersistence so Core
// stays I/O-free. UUID primary keys everywhere; bucket ids are stable and never reused.
//
// Embeddings are NOT stored on `Item` — they live in a sqlite-vec virtual table keyed by
// `itemId` (PRD §6.2 note).

/// A container for related items, typed as Account/Opportunity/Project/Topic (PRD §6.1).
public struct Bucket: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public var type: BucketType
    public var name: String
    /// Salesforce record id when `account`/`opportunity`.
    public var sfdcId: String?
    /// Altify `ALTF__Opportunity__c` id when applicable.
    public var altifyOppId: String?
    public var status: BucketStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        type: BucketType,
        name: String,
        sfdcId: String? = nil,
        altifyOppId: String? = nil,
        status: BucketStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.sfdcId = sfdcId
        self.altifyOppId = altifyOppId
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A captured or generated piece of content (PRD §6.2). Has exactly one home bucket.
public struct Item: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public var type: ItemType
    public var title: String
    public var body: String
    /// Original file path if imported.
    public var sourcePath: String?
    public var homeBucketId: UUID
    /// Classifier confidence at filing time.
    public var confidence: Double
    public var capturedVia: CaptureMethod
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        type: ItemType,
        title: String,
        body: String,
        sourcePath: String? = nil,
        homeBucketId: UUID,
        confidence: Double,
        capturedVia: CaptureMethod,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.sourcePath = sourcePath
        self.homeBucketId = homeBucketId
        self.confidence = confidence
        self.capturedVia = capturedVia
        self.createdAt = createdAt
    }
}

/// An edge in the bucket relatedness graph (PRD §6.3). Undirected semantically; store with
/// a normalized direction or both ways. `weight` drives how far prep reaches across edges.
public struct BucketLink: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public var fromBucketId: UUID
    public var toBucketId: UUID
    public var relationType: BucketLinkRelation
    public var weight: Double
    public var origin: LinkOrigin

    public init(
        id: UUID = UUID(),
        fromBucketId: UUID,
        toBucketId: UUID,
        relationType: BucketLinkRelation,
        weight: Double,
        origin: LinkOrigin
    ) {
        self.id = id
        self.fromBucketId = fromBucketId
        self.toBucketId = toBucketId
        self.relationType = relationType
        self.weight = weight
        self.origin = origin
    }
}

/// A person (PRD §6.4). `domain` is derived from email and is the key for account resolution.
public struct Contact: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var email: String?
    public var domain: String?
    public var sfdcContactId: String?
    public var linkedBucketId: UUID?

    public init(
        id: UUID = UUID(),
        name: String,
        email: String? = nil,
        domain: String? = nil,
        sfdcContactId: String? = nil,
        linkedBucketId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.domain = domain
        self.sfdcContactId = sfdcContactId
        self.linkedBucketId = linkedBucketId
    }
}

/// An attendee on a calendar event, with RSVP status from Graph (PRD §6.5).
public struct EventAttendee: Sendable, Codable, Equatable {
    public var name: String
    public var email: String?
    public var rsvp: RSVPStatus
    /// Resolved contact id when known.
    public var contactId: UUID?

    public init(name: String, email: String? = nil, rsvp: RSVPStatus = .none, contactId: UUID? = nil) {
        self.name = name
        self.email = email
        self.rsvp = rsvp
        self.contactId = contactId
    }
}

/// A calendar event synced from Microsoft Graph (PRD §6.5). Id is the Graph event id (String).
public struct CalendarEvent: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var organizerEmail: String
    public var attendees: [EventAttendee]
    public var teamsLink: String?
    /// Result of entity resolution (PRD §9).
    public var resolvedBucketId: UUID?
    public var resolutionConfidence: Double
    public var prepBriefId: UUID?

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        organizerEmail: String,
        attendees: [EventAttendee] = [],
        teamsLink: String? = nil,
        resolvedBucketId: UUID? = nil,
        resolutionConfidence: Double = 0,
        prepBriefId: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.organizerEmail = organizerEmail
        self.attendees = attendees
        self.teamsLink = teamsLink
        self.resolvedBucketId = resolvedBucketId
        self.resolutionConfidence = resolutionConfidence
        self.prepBriefId = prepBriefId
    }
}

/// A source a brief or answer drew on, surfaced for transparency (PRD §6.6, §10).
public struct SourceRef: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable {
        case localItem
        case altifyRecord
        case webSource
    }
    public var kind: Kind
    public var label: String
    /// Item id, Altify record id, or URL depending on kind.
    public var reference: String?

    public init(kind: Kind, label: String, reference: String? = nil) {
        self.kind = kind
        self.label = label
        self.reference = reference
    }
}

/// An assembled pre-call brief (PRD §6.6, §10).
public struct PrepBrief: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public var eventId: String
    public var generatedAt: Date
    /// The brief, in Markdown.
    public var content: String
    public var sources: [SourceRef]
    public var status: BriefStatus

    public init(
        id: UUID = UUID(),
        eventId: String,
        generatedAt: Date = Date(),
        content: String,
        sources: [SourceRef] = [],
        status: BriefStatus = .fresh
    ) {
        self.id = id
        self.eventId = eventId
        self.generatedAt = generatedAt
        self.content = content
        self.sources = sources
        self.status = status
    }
}

/// An item awaiting user filing in the Needs-Sorting inbox (PRD §6.7). Its ranked
/// suggestions are `ScoredBucket`s — the same shape a `FilingDecision.ambiguous` carries,
/// so an ambiguous decision flows into triage without translation.
public struct TriageItem: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public var itemId: UUID
    public var candidateBuckets: [ScoredBucket]
    /// LLM rationale shown alongside the candidates.
    public var rationale: String?
    public var reason: TriageReason
    public var status: TriageStatus

    public init(
        id: UUID = UUID(),
        itemId: UUID,
        candidateBuckets: [ScoredBucket] = [],
        rationale: String? = nil,
        reason: TriageReason,
        status: TriageStatus = .pending
    ) {
        self.id = id
        self.itemId = itemId
        self.candidateBuckets = candidateBuckets
        self.rationale = rationale
        self.reason = reason
        self.status = status
    }
}

/// A generated deliverable saved locally and surfaced as a `prep_material` item (PRD §6.8).
/// Belongs to a bucket and/or an event.
public struct Asset: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public var bucketId: UUID?
    public var eventId: String?
    public var kind: AssetKind
    public var filePath: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        bucketId: UUID? = nil,
        eventId: String? = nil,
        kind: AssetKind,
        filePath: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bucketId = bucketId
        self.eventId = eventId
        self.kind = kind
        self.filePath = filePath
        self.createdAt = createdAt
    }
}
