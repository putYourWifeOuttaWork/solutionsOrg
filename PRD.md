# PRD.md — PrepOS (working title)

> **A local-first macOS "call-prep operating system."** Pop in transcripts, notes, and CRM context; it auto-buckets them against your Salesforce/Altify records, fuses your Microsoft 365 calendar, and proactively prepares you for every call with an agentic workspace that can research, chat, and build assets.

| Field | Value |
|---|---|
| **Status** | Draft v1.0 — ready for agentic execution |
| **Owner** | Matthew (VP, AI Architecture & Solutions Engineering, Altify) |
| **Primary user** | Single user (the owner). Not multi-tenant. |
| **Target platform** | macOS, native Swift/SwiftUI |
| **Execution model** | This document is written to be executed by an autonomous coding orchestrator (e.g., Claude Code). It is the source of truth for intent. |
| **Document convention** | Spec-driven. Requirements use EARS phrasing (`WHEN <trigger> THE SYSTEM SHALL <behavior>`). Tasks carry `[P]` where parallelizable. Phase gates must pass before advancing. |

---

## 1. Mission & North Star

**Mission.** Eliminate the manual labor of call preparation. The user should never again open six tabs to remember who they're meeting, what happened last time, what's open on the deal, and what to do next. They pop material in; the system organizes it, fuses it with the calendar, and hands back a prepared, actionable brief — proactively.

**North Star metric.** *Time-to-prepared per call → near zero, with zero manual filing required for the common case.*

**Guiding philosophy (these are constraints, not flavor):**
- **Subtract, don't add.** Prefer removing user effort over adding features. Every interaction the system demands of the user is a failure mode to be designed away. (Capture must be one gesture; filing must be automatic in the common case.)
- **Minimize user effort while maximizing prep value.** The product's job is to do the methodology *for* the user so they benefit *from* it, not perform it.
- **Bounded autonomy.** The agent reads broadly and writes narrowly. For MVP it writes *nothing* to external systems. Autonomy is safe because it is assessment + (eventually, gated) bounded internal writes only — never unbounded external action.
- **You own your data.** The primary copy lives on the user's Mac, in a single encrypted file the user controls.

---

## 2. Primary user & context

- One user, one Mac. No collaboration, no sharing, no accounts/login beyond the user's own OS session.
- The user lives on mobile for *consumption* but does the real work at the Mac. Mobile is a read-only delivery target (email), never an operating surface.
- The user already operates Salesforce + Altify and has five Altify MCP connectors configured on their personal Claude account. CRM "big-picture" context = Salesforce Accounts, Opportunities, and Altify objects (assessments, relationship maps, insight cards, call plans, next-best-actions).
- The user prefers consuming by listening/reading and works in a strategic, first-principles style. Digests should be skimmable and, where possible, listenable.

---

## 3. Scope

### 3.1 In scope (MVP — Phases 1–4)
1. Frictionless local capture of transcripts, notes, documents, and CRM snippets (drag-drop, paste, share extension, watched folder, global quick-capture hotkey).
2. Automatic bucketing into a heterogeneous, evolving taxonomy (Account / Opportunity / Project / Topic) with a confidence-banded triage flow.
3. A bucket **relatedness graph** — one "home" bucket per item, with auto-linked related buckets that prep traverses.
4. **Read-only** integration with Salesforce + Altify via MCP for live record context and entity resolution.
5. Microsoft 365 / Outlook calendar fusion via Microsoft Graph.
6. Proactive prep: a **weekly digest**, a **daily digest**, and a persistent **Today / This Week** cockpit. Digests optionally emailed to self for mobile reading.
7. A **fully agentic per-call/per-bucket workspace**: chat scoped to that context, web research, and asset building (agendas, call scripts, emails, docs/decks) saved back as prep materials.
8. Security: on-device encrypted storage, Keychain-held secrets, least-privilege OAuth.

### 3.2 Out of scope / non-goals (do NOT build in MVP)
- ❌ **Any write-back to Salesforce or Altify.** The Altify Write MCP connector is *not* wired. Write is architecturally impossible in MVP, not merely policy-gated.
- ❌ Multi-user, sharing, team features, or any server-side account system.
- ❌ A mobile app or a remotely-reachable web surface. (Mobile = email delivery only.)
- ❌ Multi-device sync / CRDTs. (Single Mac is the only device. Keep the data layer clean so this is addable later, but build nothing for it now.)
- ❌ Automated meeting *recording* or live transcription. The user imports transcripts manually; the system never captures audio.
- ❌ Direct integrations with Teams/Granola/Otter/Zoom transcript pipelines. (Manual capture only.)
- ❌ Fully-local LLM inference. The system is cloud-first (Claude). Local models are not a requirement.

> **Orchestrator note:** If a task seems to require anything in §3.2, STOP and surface it as an open question rather than building it.

---

## 4. Product principles → engineering constraints

| Principle | Engineering constraint |
|---|---|
| Subtract, don't add | Capture = exactly one gesture. Common-case filing = zero gestures. No required tagging, ever. |
| Bounded autonomy | MVP = read-only externally. All external mutation paths absent from the binary. |
| You own your data | Single local SQLite file, encrypted at rest, key in Keychain. User-triggerable encrypted export. |
| Cloud-first brain, local body | Claude does reasoning/generation/decisions; local store does retrieval + persistence. Minimize what's sent: retrieve locally, send only relevant context. |
| Trust but verify the agent | Every agent action that touches the network is observable; the Today/This-Week cockpit shows what was pulled and from where. |

---

## 5. System architecture

### 5.1 Stack (decided)

| Layer | Choice | Rationale |
|---|---|---|
| UI / shell | **Native Swift / SwiftUI**, macOS 14+ (target latest stable) | Deepest access to share extension, notifications, drag-drop, menu-bar quick capture, Keychain, secure local storage. No Electron/Tauri overhead. |
| Persistence | **SQLite via GRDB.swift** + **sqlite-vec** extension | One file holds relational data *and* vector embeddings; transactional; trivial to back up and encrypt. (Avoid SwiftData for this data-critical app — known save/relationship/migration issues. Avoid Core Data unless GRDB proves insufficient.) |
| Embeddings (retrieval) | **Apple `NaturalLanguage` `NLContextualEmbedding`** (on-device, free) | Cheap, private, fast candidate generation for bucketing + retrieval. Keeps the cloud bill and egress low even though generation is cloud-first. |
| Encryption at rest | **CryptoKit (AES-GCM)** for the DB file; data key in **Keychain**; rely on FileVault for full-disk | Defense in depth on a single-user machine. |
| AI / reasoning | **Anthropic Claude Messages API** (`https://api.anthropic.com/v1/messages`) with `mcp_servers` + `web_search` tool | Cloud-first brain. MCP gives live Salesforce/Altify context; web_search gives research. Model: Sonnet for routine, Opus for heavy synthesis (configurable). |
| CRM context | **Altify MCP connectors (read servers only)** — see Appendix A | Live Accounts/Opps/Altify objects without building a Salesforce client. Read-only enforced by omitting the Write connector. |
| Calendar | **Microsoft Graph API** via **MSAL** (delegated, `Calendars.Read`) | User's schedule is in M365/Outlook. Gets Teams links + attendee RSVP status. |
| Secrets | **Keychain** (Data Protection Keychain, `...ThisDeviceOnly`) | Anthropic API key, Graph OAuth tokens, Altify MCP auth. Never `.env`, never hardcoded. |
| Scheduling | Local background timer/task + `UserNotifications` | Drives digest generation and pre-call prep. |

### 5.2 Component diagram (textual)

```
┌──────────────────────────────────────────────────────────────┐
│                    SwiftUI macOS App (sandboxed)             │
│                                                              │
│  Capture Surfaces        Bucketing Engine      Cockpit UI    │
│  • drag/drop             • local embed         • Today/Week  │
│  • paste                 • similarity match    • Bucket view │
│  • share extension  ───▶ • double-threshold ─▶ • Triage inbox│
│  • watched folder        • triage router       • Agentic chat│
│  • global hotkey         • graph linker        • Digest view │
│                                                              │
│  ┌────────────── Local Data Layer (GRDB) ─────────────────┐  │
│  │  SQLite (encrypted)  +  sqlite-vec  (single file)      │  │
│  │  Buckets · Items · BucketLinks · Contacts · Events ·   │  │
│  │  PrepBriefs · TriageItems · Assets · Settings(Keychain)│  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  Inference Provider (protocol)        Integrations          │
│  • Claude Messages API  ───────────▶  • Microsoft Graph     │
│    + mcp_servers (Altify READ)        • Altify MCP (READ)   │
│    + web_search tool                  • Outlook Mail.Send*  │
└──────────────────────────────────────────────────────────────┘
        * opt-in only, for emailing digests to self
```

### 5.3 Inference provider abstraction
Define a `ReasoningProvider` protocol so the AI backend is swappable (Claude today; a local model later without rewrites). All Claude calls go through it. It owns: model selection, MCP server config, web_search toggle, token budgeting, and the "what context is being sent" record surfaced to the cockpit.

---

## 6. Data model

> Persisted via GRDB. UUID primary keys everywhere. Embeddings live in a sqlite-vec virtual table keyed by `itemId`. Bucket IDs are **stable** so renames/merges preserve history.

### 6.1 Bucket
| Field | Type | Notes |
|---|---|---|
| id | UUID | Stable, never reused. |
| type | enum | `account` \| `opportunity` \| `project` \| `topic` |
| name | String | Display name. |
| sfdcId | String? | Salesforce record Id when `account`/`opportunity`. |
| altifyOppId | String? | Altify `ALTF__Opportunity__c` Id when applicable. |
| status | enum | `active` \| `archived` |
| prototypeRef | — | Derived from member items' embeddings (centroid + labeled exemplars). |
| createdAt / updatedAt | Date | |

### 6.2 Item
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| type | enum | `transcript` \| `note` \| `record` \| `prep_material` \| `asset` |
| title | String | Auto-derived if absent. |
| body | Text | Extracted plain text. |
| sourcePath | String? | Original file if imported. |
| homeBucketId | UUID | Exactly one home bucket. |
| confidence | Double | Classifier confidence at filing time. |
| capturedVia | enum | `dragdrop` \| `paste` \| `share` \| `watched_folder` \| `hotkey` \| `generated` |
| createdAt | Date | |
| (embedding) | vec | In sqlite-vec table, FK `itemId`. |

### 6.3 BucketLink (the relatedness graph)
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| fromBucketId / toBucketId | UUID | Undirected semantically; store both directions or normalize. |
| relationType | enum | `account_opportunity` \| `project_account` \| `topic_overlap` \| `manual` |
| weight | Double | Strength; drives how far prep reaches across edges. |
| origin | enum | `auto` \| `manual` |

### 6.4 Contact
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| name | String | |
| email | String? | |
| domain | String? | Derived from email; key for account resolution. |
| sfdcContactId | String? | |
| linkedBucketId | UUID? | Usually an account/opportunity bucket. |

### 6.5 CalendarEvent
| Field | Type | Notes |
|---|---|---|
| id | String | Microsoft Graph event id. |
| title | String | |
| start / end | Date | |
| organizerEmail | String | |
| attendees | [Contact-ref] | With RSVP status from Graph. |
| teamsLink | String? | |
| resolvedBucketId | UUID? | Result of entity resolution. |
| resolutionConfidence | Double | |
| prepBriefId | UUID? | |

### 6.6 PrepBrief
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| eventId | String | |
| generatedAt | Date | |
| content | Markdown | The brief. |
| sources | [SourceRef] | What it drew on (local items, Altify objects, web). Shown for transparency. |
| status | enum | `fresh` \| `stale` \| `dismissed` |

### 6.7 TriageItem
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| itemId | UUID | |
| candidateBuckets | [{bucketId, score}] | Top-N suggestions + LLM rationale. |
| reason | enum | `low_confidence` \| `ambiguous_two_close` \| `no_match` \| `bulk_deferred` |
| status | enum | `pending` \| `resolved` |

### 6.8 Asset
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| bucketId / eventId | ref | What it's for. |
| kind | enum | `agenda` \| `script` \| `email` \| `doc` \| `deck` \| `other` |
| filePath | String | Saved locally; also surfaces as an Item of type `prep_material`. |
| createdAt | Date | |

---

## 7. Capabilities & functional requirements (EARS)

### C1 — Capture & Ingestion
- **C1.1** WHEN the user drags a file or text onto the app (window, Dock icon, or menu-bar shelf) THE SYSTEM SHALL ingest it without requiring any further input.
- **C1.2** WHEN the user invokes the global quick-capture hotkey THE SYSTEM SHALL present a single capture field and ingest its contents on submit.
- **C1.3** WHEN content is shared to the app via the macOS share sheet THE SYSTEM SHALL ingest it.
- **C1.4** WHEN a file appears in the configured watched folder THE SYSTEM SHALL ingest it and (configurably) move it to a processed subfolder.
- **C1.5** THE SYSTEM SHALL parse `.txt`, `.md`, `.vtt`, `.srt`, `.pdf`, `.docx`, and pasted plain text into normalized item text.
- **C1.6** WHEN ingesting THE SYSTEM SHALL compute a local embedding and immediately run the bucketing pipeline (C2).
- **C1.7** THE SYSTEM SHALL NOT require the user to choose a bucket, type, or tag at capture time.

### C2 — Bucketing & Triage
- **C2.1** WHEN an item is ingested THE SYSTEM SHALL compute similarity to all bucket prototypes and attempt entity resolution against Salesforce/Altify (C4) for account/opportunity signals.
- **C2.2** WHEN the top match score ≥ `T_high` (default **0.82**, configurable) THE SYSTEM SHALL auto-file the item to that bucket silently.
- **C2.3** WHEN the item is a **single** capture and the result is ambiguous (top score in `[T_low, T_high)`, default `T_low` = **0.55`, OR the top two candidates are within `T_margin` = **0.07**) THE SYSTEM SHALL interrupt the user immediately with a bucket-picker showing ranked candidates and an LLM rationale.
- **C2.4** WHEN multiple items are ingested in a **bulk** operation (> `N_bulk`, default **3**, within a short window) THE SYSTEM SHALL suppress per-item interruption and route ambiguous items to the **Needs-Sorting** triage inbox instead.
- **C2.5** WHEN no bucket scores above `T_low` and the item is distant from all prototypes THE SYSTEM SHALL propose creating a new bucket (with a suggested type + name), routed through the same single/bulk interruption rule.
- **C2.6** WHEN the user assigns or corrects a bucket THE SYSTEM SHALL add the item's embedding as a new prototype exemplar for that bucket and update its centroid.
- **C2.7** THE SYSTEM SHALL periodically (configurable, default weekly) re-cluster prototypes and surface suggested bucket **merges/splits** to the user as non-blocking recommendations.
- **C2.8** All thresholds (`T_high`, `T_low`, `T_margin`, `N_bulk`) SHALL be user-adjustable in settings.

### C3 — Bucket Graph & Relatedness
- **C3.1** THE SYSTEM SHALL maintain `BucketLink` edges, auto-created from structural facts (an opportunity's account, a project's primary account) and from topic-overlap above a threshold.
- **C3.2** WHEN composing prep or answering in the agentic workspace THE SYSTEM SHALL traverse edges from the home bucket up to a configurable depth (default **1 hop**, weight-pruned) and include related-bucket context.
- **C3.3** THE SYSTEM SHALL let the user manually add, remove, or reweight links.

### C4 — Salesforce/Altify MCP Integration (READ-ONLY)
- **C4.1** THE SYSTEM SHALL connect to the Altify **read** MCP servers (Appendix A) via the Claude `mcp_servers` parameter. The **Write** connector SHALL NOT be configured under any circumstance in MVP.
- **C4.2** WHEN resolving an entity THE SYSTEM SHALL use Altify Salesforce find/query tools (`altify_find_acc`, `altify_find_opp`, `altify_find_contact`) to match names/domains to records.
- **C4.3** WHEN composing a prep brief for an opportunity THE SYSTEM SHALL pull, as available, the Altify call plan, next-best-actions, assessment, gaps, decision criteria, and relationship map for that opportunity.
- **C4.4** THE SYSTEM SHALL store resolved `sfdcId` / `altifyOppId` on the corresponding bucket so future resolution is instant.
- **C4.5** THE SYSTEM SHALL surface, in the cockpit, exactly which records/objects were read for any brief or chat answer (transparency).
- **C4.6** THE SYSTEM SHALL NOT invoke any tool whose effect is a write/update/create on Salesforce or Altify.

### C5 — Calendar Fusion & Entity Resolution
- **C5.1** THE SYSTEM SHALL authenticate to Microsoft Graph (MSAL, delegated `Calendars.Read`) and SHALL store tokens only in Keychain.
- **C5.2** THE SYSTEM SHALL sync upcoming events (configurable horizon, default **14 days**) on launch and on a recurring schedule.
- **C5.3** WHEN an event is synced THE SYSTEM SHALL resolve it to a bucket via: (a) attendee email **domain → account**; (b) attendee email → known Contact → bucket; (c) fuzzy match (Jaro-Winkler) of event title / attendee names to Account/Opportunity names via Altify find tools.
- **C5.4** WHEN resolution confidence is below threshold or multiple accounts match THE SYSTEM SHALL route the event to a one-tap disambiguation in the cockpit (never silently mis-resolve).
- **C5.5** THE SYSTEM SHALL treat internal-only meetings (all attendees share the user's domain) differently from external meetings (configurable: lighter prep or skip).

### C6 — Proactive Prep & Digests
- **C6.1** THE SYSTEM SHALL generate a **daily digest** each morning (configurable time) covering all of that day's external calls, each with its prep brief.
- **C6.2** THE SYSTEM SHALL generate a **weekly digest** (configurable day/time) summarizing the week ahead: notable calls, prep status, and cross-cutting themes.
- **C6.3** THE SYSTEM SHALL maintain a persistent **Today / This Week** cockpit page showing upcoming events, resolution status, brief freshness, and one-click entry into each event's agentic workspace (push + pull).
- **C6.4** THE SYSTEM SHALL refresh a brief when its underlying sources change (mark `stale`, regenerate on demand or on schedule).
- **C6.5** WHERE the user opts in, THE SYSTEM SHALL email digests to the user's own address via Graph `Mail.Send`. This is the *only* sanctioned outbound action and is OFF by default. (It is unrelated to and does not relax the SFDC/Altify read-only boundary.)
- **C6.6** Digests SHALL be skimmable and structured for optional text-to-speech consumption.

### C7 — Agentic Workspace (chat / research / build)
- **C7.1** THE SYSTEM SHALL provide, per bucket and per call, a chat surface scoped to that context (RAG over home + linked buckets + live Altify reads + web).
- **C7.2** THE SYSTEM SHALL expose tools to the agent: `web_search`, Altify MCP **read** tools, and local retrieval over the user's items.
- **C7.3** WHEN the user asks the agent to build an asset (agenda, call script, email, doc, deck) THE SYSTEM SHALL generate it, save it locally as an `Asset` + surface it as a `prep_material` Item linked to the bucket/event, and make it exportable.
- **C7.4** THE SYSTEM SHALL show provenance for agent outputs (which local items, which Altify objects, which web sources).
- **C7.5** THE SYSTEM SHALL respect a global "local-only context" awareness indicator showing what leaves the device on each call.

### C8 — Security & Privacy
See the Constitution (§12). Summarized as requirements:
- **C8.1** THE SYSTEM SHALL store the SQLite database encrypted at rest (AES-GCM), with the key in Keychain.
- **C8.2** THE SYSTEM SHALL store all secrets (Anthropic key, Graph tokens, MCP auth) only in Keychain, never in plaintext config or source.
- **C8.3** THE SYSTEM SHALL run sandboxed with hardened runtime and least-privilege entitlements.
- **C8.4** THE SYSTEM SHALL provide a user-triggered **encrypted export/backup** of all data.
- **C8.5** THE SYSTEM SHALL transmit data over TLS only and SHALL minimize context sent to Claude to what retrieval deems relevant.

---

## 8. Bucketing engine — detailed spec

**Pipeline (on every ingest):**
1. **Extract** normalized text from the source.
2. **Embed** locally (`NLContextualEmbedding`); store vector.
3. **Score** cosine similarity vs each bucket prototype (centroid + exemplars; take max).
4. **Resolve** (parallel): extract candidate org/person/opp mentions; call Altify find tools; if a confident SFDC/Altify match exists, boost the corresponding bucket's score.
5. **Decide** via double-threshold + margin:
   - `score ≥ T_high` → **auto-file** (silent).
   - `T_low ≤ score < T_high` **or** top-two within `T_margin` → **ambiguous** → single-capture interrupt *or* bulk triage queue (C2.3/C2.4).
   - `score < T_low` and far from all → **propose new bucket**.
6. **Learn**: on user correction/assignment, add exemplar + update centroid.
7. **Maintain**: scheduled re-clustering proposes merges/splits (non-blocking).

**Cold start:** before any buckets exist, classification falls back to zero-shot type/name suggestions from Claude; the first few items seed prototypes.

**Defaults:** `T_high = 0.82`, `T_low = 0.55`, `T_margin = 0.07`, `N_bulk = 3`, link traversal depth `= 1`. All user-tunable. *(These are starting points; calibrate against real data during Phase 1 acceptance.)*

---

## 9. Entity resolution — detailed spec

Order of precedence for `event → bucket`:
1. **Domain → Account.** Map each external attendee's email domain to a known account (existing bucket with `sfdcId`, or via `altify_find_acc`). Strong signal.
2. **Email → Contact → Bucket.** Direct contact match.
3. **Title / name fuzzy match** (Jaro-Winkler) to Account/Opportunity names via Altify find tools, with a similarity floor.
4. **Disambiguate** when 0 or >1 confident matches → cockpit one-tap resolution. Persist the resolution to the bucket for next time.

Internal-meeting detection: if every attendee shares the user's own domain, classify as internal (configurable prep treatment).

---

## 10. Prep brief — composition spec

For each external call, the brief assembles (as available):
- **Who** — attendees, titles, RSVP status, role on the deal (from Altify relationship map).
- **Context** — last meeting summary + open action items (from local transcripts/notes for the home + linked buckets).
- **Deal state** — Altify assessment signals, gaps, decision criteria, single-threading risk flags.
- **Next-best-actions** — pulled from Altify; framed as recommendations for *this* call.
- **Suggested agenda / talking points / smart questions** — Claude-generated from the above.
- **Linked deliverables** — relevant project assets/prep materials from linked buckets.
- **Provenance** — explicit list of sources used.

Generation runs through the `ReasoningProvider` (Claude + Altify read MCP + web_search), drawing context from local retrieval first to keep payloads minimal.

---

## 11. MCP & AI integration — detailed spec

**Claude call shape (conceptual):**
- Endpoint: `POST https://api.anthropic.com/v1/messages`.
- Model: configurable (`claude-sonnet-*` routine, `claude-opus-*` heavy synthesis).
- `mcp_servers`: the Altify **read** servers (Appendix A). **Never** the Write server.
- `tools`: `web_search` enabled for research tasks.
- Auth: API key from Keychain, injected by the provider layer; never logged.
- **Response handling:** process content blocks by `type` (`text`, `mcp_tool_use`, `mcp_tool_result`), never by position. Parse tool results as structured data.
- **Context minimization:** retrieve locally, send only relevant chunks + necessary record context.
- **Provenance capture:** record every `mcp_tool_use` (server + tool + inputs at a high level) and web source for cockpit transparency.

**Read-only enforcement (belt and suspenders):**
1. The Write connector URL is absent from configuration.
2. The provider rejects any tool name matching known write/upsert/create/update patterns.
3. The cockpit shows the user every record touched.

---

## 12. Security & Privacy Constitution (MUST / MUST-NOT)

> These are inviolable. The orchestrator MUST treat a conflict with these rules as a hard stop.

- **MUST** store all secrets (Anthropic API key, Microsoft Graph tokens, Altify MCP credentials) in the macOS Keychain using device-only accessibility. **MUST NOT** place secrets in source, `.env`, `UserDefaults`, logs, or plaintext files.
- **MUST** encrypt the local database at rest (AES-GCM, key in Keychain) and rely on FileVault for disk encryption.
- **MUST NOT** wire, import, or invoke the Altify **Write** MCP connector, or any Salesforce/Altify write/update/create/delete tool, anywhere in the MVP codebase.
- **MUST** transmit only over TLS and **MUST** minimize the context sent to any cloud model to what local retrieval deems relevant.
- **MUST** surface, per agent action, what data is leaving the device.
- **MUST NOT** record audio or perform live transcription.
- **MUST NOT** send any outbound message except the opt-in self-addressed digest email (Graph `Mail.Send`), which is OFF by default and requires explicit user enablement.
- **MUST** keep the user's data as the primary copy on-device; cloud is never the source of truth.
- **MUST** run sandboxed with hardened runtime and request only the entitlements actually used.

---

## 13. Phased delivery plan & task breakdown

> Phase gates are mandatory: do not start a phase until the prior phase's acceptance criteria pass. `[P]` marks tasks that can run in parallel. Each phase is TDD where practical (write the test, then the implementation).

### Phase 0 — Spec & guardrails
- [x] T0.1 Create `AGENTS.md` / `CLAUDE.md` encoding the Constitution (§12) as standing MUST/MUST-NOT rules. → [CLAUDE.md](CLAUDE.md)
- [x] T0.2 Stand up the Swift package/app skeleton, sandbox + hardened runtime entitlements, CI lint/test. → Swift package + CI ([Package.swift](Package.swift), [.github/workflows/ci.yml](.github/workflows/ci.yml)); macOS app target via XcodeGen ([App/project.yml](App/project.yml)) with sandbox + least-privilege entitlements; builds & launches empty.
- [x] T0.3 [P] Define the `ReasoningProvider` protocol and a no-op stub. → [ReasoningProvider.swift](Sources/PrepOSReasoning/ReasoningProvider.swift)
- **Gate:** App launches empty ✅; Constitution file present ✅; CI green ✅ (package). *(App build verified locally; app build in CI is a follow-up.)*

### Phase 1 — Local core (no calendar, no Claude)
- [x] T1.1 GRDB schema + migrations for all entities (§6); AES-GCM encryption with Keychain key (C8.1). → `PrepOSPersistence` (Schema/Records/Repositories/EncryptedDatabase). *(sqlite-vec deferred — vectors stored as BLOB, similarity in Swift; see scaffold-plan §2.)*
- [~] T1.2 [P] Capture surfaces: drag-drop, paste, global hotkey, share extension, watched folder (C1). → drag-drop + paste/quick-capture done in the app; global hotkey, share extension, watched folder pending.
- [x] T1.3 [P] Parsers for txt/md/vtt/srt/pdf/docx (C1.5). → `PrepOSParsing`.
- [x] T1.4 Local embedding service via `NLContextualEmbedding` (C1.6). → `PrepOSBucketing` (`EmbeddingService` + NL impl + deterministic fake).
- [x] T1.5 Bucketing engine: similarity scoring, double-threshold + margin, new-bucket proposal, prototype learning (C2, §8). → `PrepOSBucketing` (PrototypeIndex → FilingDecider). *(single-vs-bulk routing is the ingestion coordinator — wired with capture, T1.2.)*
- [x] T1.6 [P] Needs-Sorting triage inbox UI + on-the-spot bucket-picker. → file to a suggested bucket or create-and-file a new one.
- [~] T1.7 [P] Bucket CRUD + BucketLink graph (manual links) (C3.1, C3.3). → repositories + `BucketGraph` traversal done; manual-link UI pending.
- [x] T1.8 Encrypted export/backup (C8.4). → `EncryptedDatabase.exportEncrypted`.
- **Gate (calibrate on real data):** ≥ ~80% of clearly-belonging items auto-file correctly; ambiguous items reliably reach the right place (interrupt for singles, queue for bulk); zero plaintext secrets; backup restores cleanly. *(Engine + storage built & tested (114 tests); gate pends the capture/ingestion wiring + real-data calibration.)*

### Phase 2 — AI layer (Claude + Altify read)
- [ ] T2.1 Implement Claude `ReasoningProvider` (Keychain key, model config, block-type-aware response handling) (§11).
- [ ] T2.2 Wire Altify **read** MCP servers via `mcp_servers`; implement read-only enforcement triple-guard (§11).
- [ ] T2.3 [P] Enable `web_search` tool path.
- [ ] T2.4 Entity-resolution boost in bucketing using Altify find tools (C2.1, C4.2).
- [ ] T2.5 [P] Agentic workspace chat scoped to bucket context with provenance display (C7.1, C7.2, C7.4).
- [ ] T2.6 Manual "Generate brief for this bucket" action (precursor to proactive) (C4.3, §10).
- **Gate:** Chat answers cite local + Altify + web sources; Write connector provably absent (test asserts no write tools reachable); briefs assemble correct Altify objects.

### Phase 3 — Calendar fusion & proactive prep
- [ ] T3.1 MSAL auth to Microsoft Graph, `Calendars.Read`, tokens in Keychain (C5.1).
- [ ] T3.2 Event sync (14-day horizon, scheduled + on-launch) (C5.2).
- [ ] T3.3 Entity resolution event→bucket with disambiguation flow (C5.3, C5.4, §9).
- [ ] T3.4 [P] Today / This Week cockpit (C6.3).
- [ ] T3.5 Pre-call brief generation + freshness/staleness (C6.4, §10).
- [ ] T3.6 [P] Daily + weekly digest generation (C6.1, C6.2, C6.6).
- [ ] T3.7 [P] Opt-in self-email of digests via Graph `Mail.Send`, OFF by default (C6.5).
- [ ] T3.8 [P] Local notifications for prep-ready / pre-call.
- **Gate:** Clear-cut events resolve correctly; everything else routes to one-tap disambiguation; digests generate on schedule; email is opt-in and self-addressed only.

### Phase 4 — Agentic asset building
- [ ] T4.1 Asset generation (agenda/script/email/doc/deck) saved as `Asset` + `prep_material` Item, linked to bucket/event (C7.3).
- [ ] T4.2 [P] Export of assets to common formats.
- [ ] T4.3 [P] "Assets for this call" surfacing inside the brief and cockpit.
- **Gate:** A generated asset persists, links back to its bucket/event, appears in future prep, and exports.

### Phase 5+ — Deferred backlog (DO NOT build in MVP)
- Confirm-before-commit **write-back** to Altify/SFDC (wire Write connector behind an explicit per-write gate + audit log).
- Multi-device / mobile operating surface; sync engine selection.
- Local-model inference option behind `ReasoningProvider`.
- Direct notetaker integrations (Granola/Otter/Teams transcript pull).

---

## 14. Definition of done (MVP)

- The user can pop in a transcript/note/doc by one gesture and have it filed automatically (or routed to triage when genuinely ambiguous), with no required tagging.
- Buckets map to real Accounts/Opportunities/Altify objects; related buckets auto-link and prep pulls across them.
- The Microsoft 365 calendar is fused; each external call resolves to a bucket (or one-tap disambiguation).
- The user receives a weekly digest, a daily digest, and operates a live Today/This-Week cockpit.
- Each call has a fully agentic workspace: research, scoped chat, and asset building, all read-only against Salesforce/Altify.
- All secrets in Keychain; DB encrypted; no write paths to external systems; opt-in self-email only.

---

## 15. Open questions (resolve before or during build; do not silently assume)

1. **Threshold calibration:** the §8 defaults are guesses — confirm/tune against the user's actual corpus in Phase 1.
2. **Altify endpoint confirmation:** verify the production MCP URLs and auth method for each read connector (Appendix A lists current known values; the Account server appears to be a `dev` host — confirm).
3. **macOS minimum version:** confirm target (affects available APIs); default to the latest stable the user runs.
4. **Digest delivery time(s):** confirm preferred send times for daily/weekly.
5. **Internal-meeting handling:** confirm whether internal calls get light prep or are skipped.
6. **Asset formats:** confirm which "build" outputs matter most first (agenda/script vs deck/doc) to sequence T4.x.
7. **Model selection policy:** confirm default Sonnet-vs-Opus routing and any budget ceiling.

---

## 16. Glossary

- **Bucket** — a container for related items; typed as Account, Opportunity, Project, or Topic.
- **Home bucket** — the single bucket an item belongs to.
- **Bucket graph / BucketLink** — edges connecting related buckets; prep traverses them.
- **Triage / Needs-Sorting** — the inbox for low-confidence items awaiting user filing.
- **Prep brief** — the assembled, actionable pre-call summary.
- **Agentic workspace** — the per-call/per-bucket chat+research+build surface.
- **ReasoningProvider** — the swappable AI backend abstraction (Claude today).
- **Read-only boundary** — MVP invariant: no writes to Salesforce/Altify; Write connector unwired.

---

## Appendix A — Altify MCP connectors

**Wire these (READ) for MVP:**
| Connector | URL | Use |
|---|---|---|
| Altify Salesforce | `https://salesforce.mcp.altify.dev/mcp` | Find/query Accounts, Opportunities, Contacts (entity resolution). |
| Altify Retrieve | `https://retrieve.mcp.altify.dev/mcp` | Retrieve assessments, relationship maps, insight cards, decision criteria, sales process. |
| Altify Analysis | `https://analysis.mcp.altify.dev/mcp` | Call plans, next-best-actions, assessments, gaps, pipeline/vulnerability reads. |
| Altify Account | `https://account.mcp.dev.altify.dev/mcp` | Account-level assessment, gaps, recommendations, contact briefing. *(Confirm prod host — appears to be a dev URL.)* |

**DO NOT wire in MVP:**
| Connector | URL | Reason |
|---|---|---|
| Altify Write | `https://write.mcp.altify.dev/mcp` | Read-only boundary. Deferred to Phase 5 behind confirm-before-commit. |

## Appendix B — Microsoft Graph scopes

- `Calendars.Read` (delegated) — required, event sync.
- `User.Read` (delegated) — basic profile.
- `Mail.Send` (delegated) — **opt-in only**, for self-addressed digest email; OFF by default.
- Tokens stored in Keychain; refresh handled by MSAL.

---

*End of PRD.md*
