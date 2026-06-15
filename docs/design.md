# Design — PrepOS

Behavioral design detail. Pairs with [architecture.md](architecture.md) (structure) and
the EARS requirements in [PRD.md](../PRD.md) §7. Where this doc and the PRD disagree, the
PRD wins — open an issue.

## 1. Domain model (PRD §6) as Swift

All entities are `Sendable`, `Codable`, `Identifiable` value types in `PrepOSCore`; GRDB
record conformance is added in `PrepOSPersistence` (keep persistence concerns out of Core).

```swift
public struct Bucket: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID                 // stable, never reused
    public var type: BucketType         // account | opportunity | project | topic
    public var name: String
    public var sfdcId: String?
    public var altifyOppId: String?
    public var status: BucketStatus     // active | archived
    public var createdAt: Date
    public var updatedAt: Date
}
// Item, BucketLink, Contact, CalendarEvent, PrepBrief, TriageItem, Asset — per PRD §6.
// Embeddings live in a sqlite-vec virtual table keyed by itemId, NOT on Item.
```

`BucketPrototype` (derived, not a table row): centroid vector + labeled exemplar vectors,
recomputed as items are filed/corrected.

## 2. Configuration (PRD §8 defaults; all user-adjustable)

```swift
public struct AppConfig: Sendable, Codable {
    public var tHigh: Double = 0.82     // auto-file threshold
    public var tLow: Double = 0.55      // ambiguity floor
    public var tMargin: Double = 0.07   // top-two closeness → ambiguous
    public var nBulk: Int = 3           // > this within a window = bulk
    public var linkTraversalDepth: Int = 1
    public var calendarHorizonDays: Int = 14
}
```

## 3. Bucketing engine (PRD §8) — decision contract

Input: normalized text + embedding. Output is one of:

```swift
public enum FilingDecision: Sendable, Equatable {
    case autoFile(bucketId: UUID, score: Double)
    case ambiguous(candidates: [Candidate])     // → interrupt (single) or triage (bulk)
    case proposeNewBucket(suggestedType: BucketType, suggestedName: String)
}
public struct Candidate: Sendable, Equatable { public let bucketId: UUID; public let score: Double }
```

Decision rule (single source of truth — unit-test this exhaustively):
1. `top = max cosine(item, prototype)` over all buckets (centroid+exemplars, take max).
2. Apply entity-resolution boost: if an Altify find confidently matches a bucket's
   `sfdcId`/`altifyOppId`, raise that candidate's score (boost amount is config).
3. `score ≥ T_high` → `.autoFile`.
4. `T_low ≤ score < T_high` **or** `(top1 − top2) < T_margin` → `.ambiguous`.
5. `score < T_low` and far from all → `.proposeNewBucket`.

Routing (PRD C2.3/C2.4): `.ambiguous`/`.proposeNewBucket` for a **single** capture →
immediate interrupt; for a **bulk** capture (> `N_bulk` within the window) → Needs-Sorting
triage queue. This single-vs-bulk decision belongs to the ingestion coordinator, not the
scorer.

Learning (C2.6): on user assignment/correction, append the item's embedding as an exemplar
to the chosen bucket and recompute its centroid. Pure function over vectors — testable.

Cold start (§8): zero buckets → fall back to a zero-shot type/name suggestion from the
`ReasoningProvider`; the first few items seed prototypes.

Maintenance (C2.7): scheduled re-clustering proposes non-blocking merge/split recommendations.

## 4. Entity resolution (PRD §9) — order of precedence

`event → bucket`, stop at first confident match:
1. **Domain → Account** (external attendee email domain → known account / `altify_find_acc`).
2. **Email → Contact → Bucket**.
3. **Title/name fuzzy** (Jaro-Winkler) vs Account/Opportunity names via Altify find tools,
   with a similarity floor.
4. **Disambiguate** (0 or >1 confident) → cockpit one-tap; persist result to the bucket.

Internal-meeting detection: all attendees share the user's domain → internal (config:
lighter prep or skip). Jaro-Winkler lives in `PrepOSCore` as a pure, unit-tested function.

## 5. Reasoning layer (PRD §11) — call contract

`ReasoningRequest` → `ReasoningResponse` (already defined in `PrepOSReasoning`):
- Model routing: Sonnet routine, Opus heavy synthesis (config). Ids centralized in
  `ReasoningModel.apiModelId`.
- `mcp_servers`: Altify **read** servers only (Appendix A). Write host never present.
- `web_search`: toggled per request.
- Response handling: iterate content blocks by `type` (`text`, `mcp_tool_use`,
  `mcp_tool_result`), never by position. Record each `mcp_tool_use` as a
  `ToolInvocationRecord`; record web sources.
- `ReadOnlyGuard.validate(servers:)` runs before any network I/O; mutating tool names are
  refused.
- API key via `SecretStore`; never logged; context minimized to retrieved chunks.

## 6. Prep brief (PRD §10) — composition

Assemble, as available, for each external call: Who · Context (last meeting + open actions
from local items across home+linked buckets) · Deal state (Altify assessment/gaps/decision
criteria/single-thread risk) · Next-best-actions (Altify) · Suggested agenda/talking
points/smart questions (Claude) · Linked deliverables · **Provenance**. Local retrieval
first, then Altify reads, then web — to minimize payload. Brief marked `fresh|stale|
dismissed`; sources changing flips it `stale` (C6.4).

## 7. Digests (PRD §6.x, C6)

Daily (morning, configurable): that day's external calls each with its brief. Weekly
(configurable day/time): week-ahead themes + prep status. Structured for optional TTS
(skimmable headings, short sentences). Optional opt-in self-email via Graph `Mail.Send`
(OFF by default) — the only sanctioned outbound action.

## 8. Testing hooks (see testing-strategy.md)

Every engine exposes pure functions or protocol-injected dependencies so tests run without
Xcode/network: `EmbeddingService` (deterministic fake), `SecretStore` (in-memory),
`ReasoningProvider` (`NoOp`/scripted), GRDB on an in-memory database. The bucketing
decision rule and Jaro-Winkler are pure and exhaustively tested.
