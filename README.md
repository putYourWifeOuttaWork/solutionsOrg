# PrepOS

A local-first macOS **call-prep operating system**. Pop in transcripts, notes, and CRM
context; it auto-buckets them against your Salesforce/Altify records, fuses your Microsoft
365 calendar, and proactively prepares you for every call with an agentic workspace that
can research, chat, and build assets.

> Single-user, on-device, read-only against Salesforce/Altify. See [PRD.md](PRD.md) for the
> full product spec and [CLAUDE.md](CLAUDE.md) for the engineering constitution.

## Status

**Phase 0 — Spec & guardrails (in progress).** The core logic lives in the `PrepOSKit`
Swift Package and builds/tests from the command line today. The SwiftUI app bundle requires
Xcode (not yet installed on the dev machine) and is scaffolded but not yet buildable.

| Phase | Scope | State |
|---|---|---|
| 0 | Constitution, package skeleton, `ReasoningProvider` | 🟡 in progress |
| 1 | Local core: storage, capture, parsers, embeddings, bucketing | ⬜ |
| 2 | AI layer: Claude provider, Altify read MCP, web search, chat | ⬜ |
| 3 | Calendar fusion, digests, Today/This-Week cockpit | ⬜ |
| 4 | Agentic asset building | ⬜ |

## Build

Requires Swift 5.9+ (Command Line Tools is enough for the package):

```bash
swift build
swift test
```

## Architecture

Native Swift/SwiftUI over an encrypted SQLite (GRDB + sqlite-vec) store, with Claude
(Messages API + MCP + web search) as the cloud reasoning brain behind a swappable
`ReasoningProvider` abstraction. On-device embeddings (`NLContextualEmbedding`) keep
retrieval private and cheap. See [CLAUDE.md](CLAUDE.md) for the decided stack and rules.

## Non-negotiables

- All secrets in the **Keychain**; database **encrypted at rest**.
- **No write-back** to Salesforce/Altify — the Write connector is architecturally absent.
- No audio recording / live transcription.
- The only outbound message is an **opt-in, self-addressed** digest email (off by default).
