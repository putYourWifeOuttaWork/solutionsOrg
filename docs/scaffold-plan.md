# Scaffold plan — PrepOS

The concrete, ordered plan to take the repo from a single skeleton target to the full
multi-target package + macOS app structure, ready for the orchestrated build. Pairs with
[architecture.md](architecture.md) (target layout) and [orchestrator.md](orchestrator.md)
(the loop that runs after scaffolding).

## 0. Preconditions

- [x] Phase 0 done: Constitution, `PrepOSKit` skeleton, `ReasoningProvider`, CI.
- [ ] **Xcode installed** (`xcodes install 26.5`) — required for steps 4–5 (app target).
      Steps 1–3 (package split) proceed under Command Line Tools today.

## 1. Split the package into targets (no Xcode needed)

Restructure `Package.swift` from one `PrepOSKit` target into the layered targets from
architecture.md §2:

```
Sources/PrepOSCore/         domain model, errors, AppConfig, ID types, Jaro-Winkler
Sources/PrepOSPersistence/  GRDB records, migrations, encryption, sqlite-vec, repositories
Sources/PrepOSReasoning/    ReasoningProvider, ClaudeReasoningProvider, ReadOnlyGuard, MCP
Sources/PrepOSBucketing/    EmbeddingService, scoring, decision engine, triage, graph
Sources/PrepOSIntegrations/ Microsoft Graph client, calendar sync (logic behind protocols)
Sources/PrepOSPrep/         brief & digest composition
Tests/<Target>Tests/        per-target test suites
```

Migration of existing code: move `PrepOSKit/Reasoning/*` → `PrepOSReasoning/`, the
`PrepOS` namespace/version → `PrepOSCore/`. Update imports. `swift build && swift test`
(CI) must stay green after the split. Each target declares only its downward dependencies.

## 2. Add dependencies (no Xcode needed for resolution)

Add to `Package.swift` as targets need them:
- **GRDB.swift** — `https://github.com/groue/GRDB.swift` (Persistence).
- **sqlite-vec** — vector virtual table (Persistence). Confirm the integration path
  (SPM artifact vs vendored C). Record the decision in a design note.
- MSAL for Graph is an **app-target** dependency (added in step 4), not a package one, to
  keep package targets buildable under CLT.

Keep `PrepOSCore` dependency-free.

## 3. Establish the test scaffolding

- Deterministic `EmbeddingService` fake, scripted `ReasoningProvider`, in-memory
  `SecretStore`, in-memory GRDB.
- Port the non-negotiable boundary tests (read-only guard, no-write-host-in-`Sources/`,
  no-plaintext-secrets) into a dedicated `BoundaryTests` suite that every CI run executes.
- Add fixtures (`Tests/Fixtures/`): sample `.txt/.md/.vtt/.srt`, a tiny `.pdf`/`.docx`.

## 4. Create the macOS app target (REQUIRES Xcode) — blocked until install

Once Xcode is active:
- Create `App/PrepOSApp.xcodeproj` (or an Xcode workspace referencing the SPM package) with
  a SwiftUI macOS app target `PrepOSApp`, deployment target macOS 14.
- Add the package as a local dependency; the app links all package products.
- Implement the app-only protocols: `SecretStore` (Keychain), `EmbeddingService`
  (`NLContextualEmbedding`), file/notification services.
- Stub the main scenes: Today/This-Week cockpit, Triage inbox, Bucket view, Agentic chat,
  Digest view, Settings — empty but navigable (closes the "app launches empty" gate).

## 5. Entitlements & signing (REQUIRES Xcode) — blocked until install

- Enable **App Sandbox** + **Hardened Runtime**.
- Least-privilege entitlements only (see [security-constitution.md](security-constitution.md)
  §7): user-selected file access, outgoing network (client). **No** microphone/camera/write.
- Add the **share extension** target and **watched-folder** + **global hotkey** plumbing
  as their own pieces (Phase 1 T1.2).
- Configure local signing for development.

## 6. Kickoff workflow (after scaffold + Xcode)

Once steps 1–5 are done, the orchestrator launches the build via the loop in
orchestrator.md §2. As a `Workflow`, Phase 1 looks like:

```
phase('Phase 1 — Local core')
const PIECES = [P1a_domain, P1b_persistence, P1c_parsers, P1d_embedding,
                P1e_bucketing, P1f_graph, P1g_backup]   // P1h capture UI is Xcode-gated
const results = await pipeline(PIECES,
  p  => agent(architectPrompt(p), {agentType:'swift-architect', phase:'Design', schema:DESIGN}),
  d  => agent(buildPrompt(d),     {agentType:'swift-builder',  phase:'Build'}),   // runs /simplify
  b  => agent(qaPrompt(b),        {agentType:'qa-engineer',    phase:'QA', schema:QA_VERDICT}),
  q  => agent(auditPrompt(q),     {agentType:'security-auditor',phase:'Audit', schema:AUDIT})
)
// orchestrator judges each result vs PRD acceptance; reopens pieces that fail; recurses.
```

Independent pieces run in parallel (distinct targets → no collisions). The builder⇄QA
recursion and the auditor veto are enforced per orchestrator.md. The orchestrator judges
success and recurses until the Phase 1 gate (PRD §13) passes, then advances.

## 7. Order of operations (summary)

1. Split targets (CLT) → green CI.
2. Add GRDB + sqlite-vec; build test scaffolding + boundary tests + fixtures (CLT).
3. *(Xcode)* Create app target + empty navigable scenes → app-launches-empty gate.
4. *(Xcode)* Entitlements, sandbox, hardened runtime, share extension, hotkey, watched folder.
5. Launch the orchestrated Phase 1 build loop; gate; advance through Phases 2–4.

Steps 1–2 can start now; 3–4 unblock when Xcode finishes installing.
