# Architecture — PrepOS

Derived from [PRD.md](../PRD.md) §5. This doc is the authoritative map of *structure*:
targets, modules, dependencies, and data flow. Design *behavior* lives in
[design.md](design.md).

## 1. Principles → structure

| Principle (PRD §4) | Structural consequence |
|---|---|
| Cloud-first brain, local body | Reasoning is isolated behind `ReasoningProvider`; retrieval/persistence are local and never depend on the cloud. |
| You own your data | One encrypted SQLite file is the system of record. No cloud store. |
| Bounded autonomy | No external-write code paths exist in the binary. `ReadOnlyGuard` is the runtime backstop. |
| Subtract, don't add | Capture surfaces feed one ingestion pipeline; no per-item user input required. |
| Trust but verify | Every cloud call records a `ContextDisclosure` + `ToolInvocationRecord` for the cockpit. |

## 2. Targets & dependency graph

The core is split into small SPM library targets so independent agents can build in
parallel without file collisions. The app bundle is a separate Xcode target on top.

```
                     ┌─────────────┐
                     │ PrepOSCore  │  domain model, errors, config, IDs
                     └──────┬──────┘
        ┌───────────────────┼───────────────────┬───────────────────┐
        ▼                   ▼                   ▼                   ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│PrepOSPersist. │  │PrepOSReasoning│  │PrepOSIntegr.  │  │  (test utils) │
│ GRDB store    │  │ provider, MCP │  │ Graph/calendar│  │  fixtures     │
│ encryption    │  │ ReadOnlyGuard │  │ MSAL auth     │  └───────────────┘
│ sqlite-vec    │  │ web_search    │  └───────┬───────┘
└───────┬───────┘  └───────┬───────┘          │
        │                  │                  │
        ▼                  │                  │
┌───────────────┐          │                  │
│PrepOSBucketing│          │                  │
│ embeddings    │◀─────────┘ (entity-resolution boost via Reasoning)
│ scoring/triage│
│ bucket graph  │
└───────┬───────┘
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│ PrepOSPrep — brief & digest composition (orchestrates all above)│
└───────────────────────────┬───────────────────────────────────┘
                            ▼
┌───────────────────────────────────────────────────────────────┐
│ PrepOSApp (Xcode target) — SwiftUI shell, share extension,     │
│ watched folder, global hotkey, notifications, entitlements      │
└───────────────────────────────────────────────────────────────┘
```

**Rule:** dependencies point downward only. `PrepOSCore` depends on nothing. App-only
frameworks (AppKit, share-extension APIs, `UserNotifications`) appear **only** in
`PrepOSApp`; package targets expose protocols the app implements, so the core stays
testable under Command Line Tools.

> Current state: everything lives in a single `PrepOSKit` target. The scaffold
> ([scaffold-plan.md](scaffold-plan.md)) performs the split above.

## 3. Target responsibilities

### PrepOSCore
Domain model (PRD §6) as value types: `Bucket`, `Item`, `BucketLink`, `Contact`,
`CalendarEvent`, `PrepBrief`, `TriageItem`, `Asset`. Enums for types/status. `AppConfig`
(thresholds `T_high`/`T_low`/`T_margin`/`N_bulk`, traversal depth). Stable UUID id types.
No I/O.

### PrepOSPersistence
GRDB record types + migrations for every entity. AES-GCM-at-rest via a `DatabaseKey`
pulled from Keychain (protocol `SecretStore`, real impl in app, in-memory fake in tests).
`sqlite-vec` virtual table for embeddings keyed by `itemId`. Encrypted export/backup
(C8.4). Repositories expose query/persist APIs to higher targets.

### PrepOSReasoning
`ReasoningProvider` protocol + `ClaudeReasoningProvider` (Messages API, `mcp_servers`,
`web_search`) + `NoOpReasoningProvider`. `ReadOnlyGuard` (write-host/tool rejection).
Block-type-aware response parsing. Records `ContextDisclosure` + `ToolInvocationRecord`.
The API key is fetched via `SecretStore`, never logged.

### PrepOSBucketing
`EmbeddingService` protocol (real impl wraps `NLContextualEmbedding`; deterministic fake
for tests). Similarity scoring vs bucket prototypes (centroid + exemplars). Double-
threshold + margin decision (§8). Single-vs-bulk routing. New-bucket proposal. Prototype
learning on correction. Bucket relatedness graph + traversal. Entity-resolution boost
calls Altify find tools via `PrepOSReasoning`.

### PrepOSIntegrations
Microsoft Graph client via MSAL (delegated `Calendars.Read`, optional `Mail.Send`). Event
sync (14-day horizon). Token storage via `SecretStore` (Keychain). No SFDC client — CRM
context comes through Altify MCP in `PrepOSReasoning`.

### PrepOSPrep
Prep-brief composition (§10), daily/weekly digests (C6), staleness tracking. Pulls local
retrieval first, then live Altify reads, then web — minimizing cloud payloads. Produces
provenance.

### PrepOSApp (Xcode)
Capture surfaces (drag-drop, paste, share extension, watched folder, global hotkey),
Today/This-Week cockpit, triage inbox, agentic workspace chat UI, digest views,
settings, notifications. Implements `SecretStore` (Keychain) and `EmbeddingService`
(NaturalLanguage). Sandbox + hardened runtime + least-privilege entitlements.

## 4. Key data flow — ingest → file

```
capture surface → normalize text (parser) → EmbeddingService.embed
   → BucketingEngine.score(vs prototypes) ∥ EntityResolver.resolve(Altify reads)
   → decide(double-threshold + margin)
        score ≥ T_high                → auto-file (silent)
        T_low ≤ score < T_high | tie  → single: interrupt | bulk: triage queue
        score < T_low (far)           → propose new bucket
   → persist Item + embedding; on correction → learn(prototype exemplar + centroid)
```

## 5. Key data flow — calendar → prep

```
Graph sync → CalendarEvent → EntityResolver(domain→account, email→contact, fuzzy title)
   → resolvedBucketId (or one-tap disambiguation)
   → PrepComposer: local retrieval (home + linked buckets) + Altify reads + web
   → PrepBrief (markdown + sources) → cockpit + optional self-email digest
```

## 6. Cross-cutting concerns

- **Provenance**: every cloud call returns disclosures + tool records; surfaced in cockpit
  (PRD C4.5, C7.4, C7.5).
- **Configuration**: all thresholds user-adjustable; defaults in `AppConfig` (PRD §8).
- **Errors**: typed per target; the read-only boundary surfaces as
  `ReasoningError.writeToolForbidden`.
- **Concurrency**: value types are `Sendable`; providers/services are `async` and
  `Sendable`; persistence serializes writes through GRDB's database queue.
