# Security & Privacy Constitution — engineering checklist

The inviolable rules ([CLAUDE.md §1](../CLAUDE.md), PRD §12) turned into concrete
engineering obligations. The `security-auditor` agent gates every piece against this list
and holds **veto** power.

## 1. Secrets → Keychain only

- Anthropic API key, Microsoft Graph tokens, Altify MCP credentials live in the macOS
  **Keychain** (Data Protection Keychain, accessibility `...ThisDeviceOnly`).
- Access via a `SecretStore` protocol; the real Keychain impl lives in the app target, an
  in-memory fake in tests. Package code never reads Keychain directly.
- **MUST NOT** appear in: source, `.env`, `UserDefaults`, logs, plaintext config, commit
  history. `.gitignore` blocks `*.env`, `secrets.json`, `*.p8`, `*.p12`.
- Logging: never log secret values or full request bodies. Provenance logs record
  high-level inputs only.

## 2. Encryption at rest

- The SQLite database file is encrypted with **AES-GCM** (CryptoKit). The data key is
  generated on first run, stored in Keychain, never written to disk in plaintext.
- Rely on FileVault for full-disk encryption (defense in depth).
- Encrypted export/backup (C8.4) re-encrypts under a user-controlled key.

## 3. Read-only boundary (Salesforce/Altify) — triple guard

1. **Configuration:** the Write connector URL (`https://write.mcp.altify.dev/mcp`) is
   absent from all config. Only the four read servers (PRD Appendix A) are wired.
2. **Runtime:** `ReadOnlyGuard` rejects (a) any MCP server on a known write host, and
   (b) any tool name containing write/upsert/create/update/delete/insert/set_/modify/remove
   — before any network I/O.
3. **Transparency:** the cockpit lists every record/object touched per brief or answer.

Tests assert the boundary (see [testing-strategy.md](testing-strategy.md) §3). Write must be
*architecturally impossible*, not policy-gated.

## 4. Network & data minimization

- TLS only. Retrieve locally first; send the cloud only the relevant chunks + necessary
  record context.
- Every cloud call records a `ContextDisclosure` (what left the device) and
  `ToolInvocationRecord` (which tools/servers were used) for the cockpit.

## 5. No audio / no live transcription

- The app never captures audio or runs transcription. Transcripts are imported manually.
  No microphone entitlement is requested.

## 6. Outbound messages

- The **only** sanctioned outbound message is the **opt-in, self-addressed** digest email
  via Graph `Mail.Send`. It is OFF by default and requires explicit user enablement. No
  other send path exists. The opt-in does **not** relax the SFDC/Altify read-only boundary.

## 7. Sandbox & entitlements (app target)

- App Sandbox + Hardened Runtime enabled. Request only what is used:
  - File access for drag-drop/share/watched-folder (user-selected / security-scoped).
  - Outgoing network (client) for Claude/Graph/MCP over TLS.
  - `Mail.Send` Graph scope only when the user opts in; `Calendars.Read` + `User.Read`
    otherwise.
  - **No** microphone, camera, or write entitlements beyond what the above require.

## 8. Auditor gate (per piece)

Block the piece if any is true:
- A secret could reach source/logs/config/`UserDefaults`.
- The DB (or an export) could be written unencrypted.
- Any code path could reach a Salesforce/Altify write tool or the write host.
- A cloud call omits provenance recording.
- An entitlement is requested that the piece does not actually use.
- An outbound message other than the opt-in self-email is possible.
