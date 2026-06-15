---
name: constitution-check
description: Audit PrepOS code against the inviolable Security & Privacy Constitution — no Salesforce/Altify write paths, secrets only in Keychain, DB encrypted, provenance recorded, least-privilege entitlements, no audio capture. Use before merging, when reviewing a piece, or when the user asks "is this safe / compliant / constitutional?".
---

# Constitution check

Audit the current changes (or a named piece) against
[docs/security-constitution.md](../../../docs/security-constitution.md). This mirrors the
`security-auditor` agent's gate; run it inline for a quick check.

## Checks (block on ANY failure)

1. **Secrets → Keychain only.** Grep `Sources/` and the diff for hardcoded key/token
   patterns, `UserDefaults`, and logging of secrets or full request bodies. Secrets must
   flow only through `SecretStore`.
   ```bash
   grep -rniE 'sk-ant|api[_-]?key *=|bearer |password *=|UserDefaults' Sources/ || echo "clean"
   ```

2. **No Salesforce/Altify write path.** The write host must appear nowhere; `ReadOnlyGuard`
   must run before network I/O.
   ```bash
   grep -rni 'write.mcp.altify.dev' Sources/ && echo "VIOLATION" || echo "no write host"
   grep -rniE 'upsert|altify_create|altify_update|altify_delete' Sources/ || echo "no write tools"
   ```

3. **Encryption at rest.** The DB and any export are AES-GCM encrypted; the data key comes
   from Keychain and never hits disk in plaintext.

4. **Provenance.** Cloud-touching code records `ContextDisclosure` + `ToolInvocationRecord`.

5. **Entitlements.** Only what's used; no microphone/camera/write entitlements.

6. **No audio / transcription.** No audio-capture or live-transcription path.

7. **Outbound.** Only the opt-in, self-addressed digest email is possible.

## Output
For each check: PASS (with what you verified) or VIOLATION (file:line + the rule broken).
Any violation blocks the merge until fixed — the Constitution is inviolable.
