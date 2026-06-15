# CLAUDE.md — PrepOS engineering constitution & working notes

This file is loaded into context every session. It is the **standing law** for building
PrepOS. [PRD.md](PRD.md) is the source of truth for *intent*; this file is the source of
truth for *how we build and what we must never do*.

If a task appears to require anything forbidden below, **STOP and surface it as an open
question** rather than building it.

---

## 1. The Security & Privacy Constitution (inviolable — PRD §12)

Treat any conflict with these as a **hard stop**.

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
   delete patterns before dispatch.
3. The cockpit shows the user every record touched.

---

## 2. Architecture (decided — PRD §5)

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

### Repo layout
```
PRD.md                     Source of truth for intent
CLAUDE.md                  This file — standing rules
Package.swift              Swift Package (core logic — builds under CLT, no Xcode needed)
Sources/PrepOSKit/         Core library: domain model, reasoning, bucketing, parsers, …
Tests/PrepOSKitTests/      Unit tests (swift test)
App/                       (Phase 0+) SwiftUI app target — REQUIRES Xcode to build
.github/workflows/ci.yml   CI: swift build + swift test
```

The core logic lives in the **`PrepOSKit` Swift Package** and is fully testable from the
command line. The macOS **app bundle** (SwiftUI shell, share extension, entitlements)
requires **full Xcode** — see §4.

---

## 3. Build & test

```bash
swift build            # compile the core library
swift test             # run the unit tests
```

These work with **Command Line Tools** alone — no Xcode required. CI runs both on every push.

**Before committing:** `swift build && swift test` must pass.

---

## 4. Known environment constraint

Full **Xcode is not installed** on the dev machine (only Command Line Tools, Swift 5.10).
Consequences:
- ✅ The `PrepOSKit` package builds and tests via `swift`/CLT today.
- ⛔ The SwiftUI **app bundle**, **share extension**, **sandbox/hardened-runtime
  entitlements**, and on-device frameworks that need an app context cannot be compiled
  until Xcode is installed. Scaffold them so they are ready, but do not claim they build.

When code depends on app-only frameworks, isolate it behind protocols in `PrepOSKit` so the
logic stays testable without Xcode.

---

## 5. Working agreement

- **TDD where practical**: write the test, then the implementation (PRD §13).
- **Phase gates are mandatory**: do not start a phase until the prior phase's acceptance
  criteria pass. Track progress against the PRD §13 task IDs (T0.1, T1.1, …).
- **Keep this repo up to date as we build**: commit working increments with clear messages;
  update this file and the PRD checklist as tasks complete.
- `[P]` tasks in the PRD may be parallelized.
- UUID primary keys everywhere; bucket IDs are stable (never reused) so renames/merges
  preserve history.
- Process Claude response content blocks **by `type`**, never by position.

---

## 6. Phase status

- [x] **Phase 0** — Spec & guardrails (CLAUDE.md, package skeleton, `ReasoningProvider`)
- [ ] **Phase 1** — Local core (GRDB schema, capture, parsers, embeddings, bucketing)
- [ ] **Phase 2** — AI layer (Claude provider, Altify read MCP, web_search, agentic chat)
- [ ] **Phase 3** — Calendar fusion & proactive prep (Graph, digests, cockpit)
- [ ] **Phase 4** — Agentic asset building

Update this checklist as phase gates pass.
