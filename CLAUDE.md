# CLAUDE.md — PrepOS engineering constitution & orchestration charter

This file is loaded into context every session. It is the **standing law** for building
PrepOS. [PRD.md](PRD.md) is the source of truth for *intent*; this file is the source of
truth for *how we build, what we must never do, and how the agents coordinate*.

If a task appears to require anything forbidden in §1, **STOP and surface it as an open
question** rather than building it.

**Document map**
| Doc | Purpose |
|---|---|
| [PRD.md](PRD.md) | Product spec — intent, scope, requirements (EARS), phase plan |
| **CLAUDE.md** (this) | Standing rules, stack, orchestration charter |
| [docs/architecture.md](docs/architecture.md) | System & module/target architecture |
| [docs/design.md](docs/design.md) | Detailed design: data model, engines, protocols |
| [docs/orchestrator.md](docs/orchestrator.md) | The build-loop playbook & agent roster |
| [docs/testing-strategy.md](docs/testing-strategy.md) | TDD, CI, acceptance gates |
| [docs/security-constitution.md](docs/security-constitution.md) | Constitution → engineering checklist |
| [docs/scaffold-plan.md](docs/scaffold-plan.md) | Step-by-step app scaffold plan |

---

## 1. The Security & Privacy Constitution (inviolable — PRD §12)

Treat any conflict with these as a **hard stop**. Full engineering detail in
[docs/security-constitution.md](docs/security-constitution.md).

**MUST**
- Store every secret (Anthropic API key, Microsoft Graph tokens, Altify MCP credentials)
  in the macOS **Keychain** with device-only accessibility (`...ThisDeviceOnly`).
- Encrypt the local SQLite database at rest (**AES-GCM**, key in Keychain); rely on
  FileVault for full-disk encryption.
- Transmit only over **TLS**, and minimize the context sent to any cloud model to what
  local retrieval deems relevant.
- Surface, per agent action, exactly what data is leaving the device (provenance).
- Keep the user's data as the **primary copy on-device**; cloud is never the source of truth.
- Run **sandboxed** with hardened runtime, requesting only the entitlements actually used.

**MUST NOT**
- Place secrets in source, `.env`, `UserDefaults`, logs, or any plaintext file.
- Wire, import, or invoke the Altify **Write** MCP connector
  (`https://write.mcp.altify.dev/mcp`) or **any** Salesforce/Altify write/update/create/
  delete tool, anywhere in the MVP codebase. Write must be *architecturally impossible*,
  not merely policy-gated.
- Record audio or perform live transcription. (Transcripts are imported manually.)
- Send any outbound message except the **opt-in, self-addressed** digest email via Graph
  `Mail.Send` — OFF by default, requires explicit user enablement.

### Read-only enforcement — belt & suspenders (PRD §11)
1. The Write connector URL is **absent** from all configuration.
2. The provider layer **rejects** any tool name matching write/upsert/create/update/
   delete patterns before dispatch (`ReadOnlyGuard`).
3. The cockpit shows the user every record touched.

---

## 2. Architecture (decided — PRD §5; detail in docs/architecture.md)

| Layer | Choice |
|---|---|
| UI / shell | Native **Swift / SwiftUI**, macOS 14+ |
| Persistence | **SQLite via GRDB.swift** + **sqlite-vec** (one encrypted file) |
| Embeddings | Apple `NaturalLanguage` `NLContextualEmbedding` (on-device) |
| Encryption | **CryptoKit** AES-GCM; data key in Keychain |
| AI / reasoning | **Anthropic Claude Messages API** + `mcp_servers` + `web_search` |
| CRM context | Altify MCP **read** servers only (PRD Appendix A) |
| Calendar | **Microsoft Graph** via **MSAL** (delegated `Calendars.Read`) |
| Secrets | Keychain (Data Protection, device-only) |

All Claude calls go through the `ReasoningProvider` protocol so the backend is swappable.

### Target / module layout (scaffold target — see docs/scaffold-plan.md)
The core splits into focused SPM library targets so agents work on independent surfaces
without colliding. The macOS app bundle is a separate Xcode target on top.
```
PrepOSCore          domain model, errors, config              (no deps)
PrepOSPersistence   GRDB store, encryption, sqlite-vec         → Core
PrepOSReasoning     ReasoningProvider, MCP, ReadOnlyGuard      → Core
PrepOSBucketing     embedding, scoring, triage, graph          → Core, Persistence
PrepOSIntegrations  Microsoft Graph / calendar                 → Core
PrepOSPrep          brief & digest composition                 → all of the above
PrepOSApp (Xcode)   SwiftUI shell, share extension, entitlements → all
```
Until the scaffold runs, all code lives in the single `PrepOSKit` target.

---

## 3. Build & test

```bash
swift build            # compile the core library/targets
swift test             # run the unit tests
```

These work with **Command Line Tools** alone — no Xcode required. CI runs both on every push.
**Before committing:** `swift build && swift test` must pass.

---

## 4. Toolchain

**Xcode 26.5 is the active toolchain** (`xcode-select -p` → `/Applications/Xcode.app`,
Swift 6.3.2). No `DEVELOPER_DIR` prefix needed.

- ✅ `swift build` and `swift test` both run locally (all package tests green).
- ✅ The macOS **app bundle** builds: `cd App && xcodegen generate && xcodebuild -project
  PrepOS.xcodeproj -scheme PrepOSApp -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`.
- The Xcode project is **generated from `App/project.yml` via XcodeGen** (the `.xcodeproj`
  and `.entitlements` are gitignored derived artifacts). Edit `project.yml`, not the project.
- Keep app-only framework use (AppKit, share extension, `NaturalLanguage`, Keychain) behind
  protocols in the package so the core stays testable in isolation.

---

## 5. Orchestration charter (how the agents build this)

PrepOS is built by a roster of specialized subagents coordinated by an **orchestrator**.
Full playbook: [docs/orchestrator.md](docs/orchestrator.md). The core loop:

```
orchestrator decomposes a phase into independent PIECES
  └─ for each piece:
       architect  → writes/updates the piece's design note
       builder    → implements it TDD-first (test, then code)
       /simplify  → builder runs the simplify skill on the new code
       qa-engineer→ verifies acceptance criteria + runs tests; files defects
       (loop builder ⇄ qa-engineer until the piece passes QA)
       security-auditor → Constitution gate (read-only, Keychain, encryption)
  orchestrator reviews the piece vs the PRD acceptance criteria → success | redo
  (recurse until every piece in the phase is done → phase gate)
```

**Realization in this harness:** the orchestrator is the main session (or a `Workflow`
script) driving the `Agent` tool. Subagents cannot spawn subagents, so fan-out and the
build⇄QA recursion are owned by the orchestrator layer. Parallel builders use **separate
SPM targets or git worktrees** to avoid file collisions.

**Standing rules for every agent:**
- Obey §1 without exception. The `security-auditor` has veto power.
- TDD where practical; `swift build && swift test` green before declaring a piece done.
- A "new piece" finished by a builder MUST be followed by `/simplify`, then QA — recurse
  until QA passes. Do not skip the loop.
- Keep this repo up to date: commit working increments with clear messages; update the
  §6 phase checklist and the PRD §13 task boxes as gates pass.
- Process Claude response content blocks **by `type`**, never by position.
- UUID primary keys everywhere; bucket IDs are stable (never reused).

---

## 6. Phase status

- [x] **Phase 0** — Spec & guardrails (CLAUDE.md, package skeleton, `ReasoningProvider`)
- [~] **Phase 1** — Local core. Package layer DONE (persistence+encryption, parsers, embedding, bucketing engine, graph; 114 tests). Pending: capture surfaces + triage UI (app, T1.2/T1.6) and ingestion-coordinator wiring → then the real-data gate.
- [ ] **Phase 2** — AI layer (Claude provider, Altify read MCP, web_search, agentic chat)
- [ ] **Phase 3** — Calendar fusion & proactive prep (Graph, digests, cockpit)
- [ ] **Phase 4** — Agentic asset building

Update this checklist as phase gates pass.
