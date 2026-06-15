# Testing strategy — PrepOS

Pairs with [PRD.md](../PRD.md) §13 (phase gates) and [orchestrator.md](orchestrator.md)
(the QA step of the build loop). TDD where practical: write the test, then the code.

## 1. Environment reality

- **Local (Command Line Tools, no Xcode):** `swift build` works; `swift test` does **not**
  (XCTest needs Xcode). For local verification, compile a `main.swift` driver against the
  sources and assert (the Phase 0 pattern). Pure functions and protocol-injected
  dependencies make this easy.
- **CI (`macos-14`, Xcode present):** `swift build && swift test` run on every push
  ([.github/workflows/ci.yml](../.github/workflows/ci.yml)). This is the authoritative gate.
- Once Xcode is installed locally, `swift test` runs locally too.

## 2. Test layers

| Layer | What | Runs where |
|---|---|---|
| Unit (pure) | Bucketing decision rule, Jaro-Winkler, prototype learning math, `ReadOnlyGuard`, parsers. | CI + CLT driver |
| Unit (injected deps) | Persistence on in-memory GRDB; reasoning with `NoOp`/scripted provider; embedding with deterministic fake; `SecretStore` in-memory fake. | CI |
| Contract | `ReasoningProvider` conformances behave identically for the read-only boundary. | CI |
| Integration | Ingest→file pipeline end-to-end with fakes; event→bucket resolution. | CI |
| App/UI | SwiftUI flows, capture surfaces. | **Blocked on Xcode**; manual + later XCUITest |

## 3. Non-negotiable tests (the boundary)

These must exist and stay green for the life of the project:
- `ReadOnlyGuard` rejects the Altify Write host and every write/upsert/create/update/
  delete tool name; allows the read tools (find/query/read/get).
- No `ReasoningProvider` can dispatch to a write-capable server (asserted in a contract test).
- A grep-style test asserts the Write connector URL appears **nowhere** in `Sources/`.
- Secrets never appear in source: a test scans for hardcoded key patterns.

## 4. Fixtures

- Sample transcripts/notes (`.txt/.md/.vtt/.srt`) + a small `.pdf`/`.docx` for parser tests.
- Deterministic embedding fake: maps known strings → fixed vectors so similarity outcomes
  are predictable and the decision rule is testable to the threshold.
- Scripted reasoning provider: returns canned content blocks (text + `mcp_tool_use` +
  `mcp_tool_result`) to test block-type-aware parsing and provenance capture.

## 5. Acceptance gates (map to PRD §13)

- **Phase 1:** ≥~80% of clearly-belonging items auto-file; ambiguous singles interrupt,
  bulk routes to triage; zero plaintext secrets; backup restores cleanly. Calibrate
  thresholds on real data.
- **Phase 2:** chat cites local + Altify + web sources; a test asserts no write tools are
  reachable; briefs assemble the correct Altify objects.
- **Phase 3:** clear-cut events resolve; the rest route to one-tap disambiguation; digests
  generate on schedule; email is opt-in, self-addressed only.
- **Phase 4:** a generated asset persists, links back to its bucket/event, appears in future
  prep, and exports.

## 6. QA-engineer checklist (build loop step 5)

For each piece: acceptance criteria met? tests cover happy + edge + boundary? `swift
build && swift test` green? `/code-review` clean? public API documented? provenance
recorded where cloud is touched? If any "no," file a specific defect and bounce to the
builder.
