# Orchestrator playbook — how PrepOS gets built

This is the operating manual for autonomous, multi-agent construction of PrepOS. It defines
the agent roster, the recursive build loop, how work is decomposed, how collisions are
avoided, and what "done" means at each level. The orchestrator (main session or a
`Workflow` script) owns this loop end to end.

## 1. Agent roster

Subagent definitions live in [`.claude/agents/`](../.claude/agents). Each has a single
responsibility; the orchestrator composes them.

| Agent | Role | Key tools |
|---|---|---|
| **orchestrator** | Decompose phases → pieces, assign, drive the loop, judge success, recurse. | Agent, Task*, Bash, Read, Workflow |
| **swift-architect** | Before a piece is built, produce/refresh its short design note (types, protocols, test list) consistent with docs/. | Read, Write, Grep |
| **swift-builder** | Implement a piece TDD-first; run `/simplify` on new code; keep `swift build && swift test` green. | Read, Write, Edit, Bash, Skill |
| **qa-engineer** | Verify the piece against PRD acceptance criteria; run/extend tests; file precise defects. | Read, Bash, Grep, Skill |
| **security-auditor** | Constitution gate (§1): no write paths, secrets only in Keychain, encryption present, provenance recorded. Has **veto**. | Read, Grep, Bash |

Subagents **cannot spawn subagents** in this harness. All fan-out and recursion are owned
by the orchestrator layer (the main session or a `Workflow` script calling `agent()`).

## 2. The recursive build loop

For each **piece** (smallest independently-shippable unit — usually one target subsystem
or one PRD task like T1.4):

```
1. architect   → design note exists & matches docs/  ........ else write it
2. builder     → write failing test(s), then implementation
3. builder     → /simplify on the new code (reuse, dedupe, altitude)
4. builder     → swift build && swift test green
5. qa-engineer → verify acceptance criteria; run tests; /code-review
                 ├─ defects? → back to step 2 (builder fixes)  ◀── recurse
                 └─ clean    → continue
6. security-auditor → Constitution gate
                 ├─ violation? → back to step 2 (HARD STOP until fixed) ◀── recurse
                 └─ pass       → piece is CANDIDATE-DONE
7. orchestrator → judge piece vs PRD acceptance criteria
                 ├─ not satisfied → reopen with specific gap   ◀── recurse
                 └─ satisfied     → piece DONE; commit
```

The builder⇄qa recursion (steps 2–5) repeats until QA is clean. The auditor gate (step 6)
is non-negotiable. Only the orchestrator declares a piece DONE (step 7).

## 3. Decomposition: phase → pieces

The orchestrator reads PRD §13 and turns each phase's tasks into pieces sized for one
builder pass. Example for **Phase 1**:

| Piece | PRD task | Target | Depends on |
|---|---|---|---|
| P1-a Domain model | (part of T1.1) | PrepOSCore | — |
| P1-b GRDB schema + encryption + sqlite-vec | T1.1 | PrepOSPersistence | P1-a |
| P1-c Parsers (txt/md/vtt/srt/pdf/docx) | T1.3 | PrepOSCore/Parsing | P1-a |
| P1-d Embedding service (+ fake) | T1.4 | PrepOSBucketing | P1-a |
| P1-e Bucketing decision engine | T1.5 | PrepOSBucketing | P1-a, P1-d |
| P1-f Bucket graph + links | T1.7 | PrepOSBucketing | P1-a, P1-b |
| P1-g Encrypted export/backup | T1.8 | PrepOSPersistence | P1-b |
| P1-h Capture surfaces + triage UI | T1.2, T1.6 | PrepOSApp | rest (needs Xcode) |

Independent pieces (no shared dependency, different targets) run in **parallel** builders.
`[P]`-marked PRD tasks are the parallelization hint.

## 4. Collision avoidance

- **Different targets → safe parallelism.** Assign each parallel builder a distinct SPM
  target/folder. Two builders never edit the same file concurrently.
- When parallel work must touch overlapping files, use **git worktrees**
  (`isolation: "worktree"` for `Workflow` agents) and merge sequentially.
- Shared contracts (protocols in `PrepOSCore`) are defined by the architect **first**, then
  frozen for the duration of the parallel batch.

## 5. Phase gating

A phase is DONE only when every piece is DONE **and** the PRD §13 phase gate passes
(e.g., Phase 1: "≥~80% of clearly-belonging items auto-file; ambiguous items route
correctly; zero plaintext secrets; backup restores cleanly"). The orchestrator runs the
gate explicitly, records the result, ticks CLAUDE.md §6 + the PRD checkbox, commits, and
only then starts the next phase. **No phase starts before the prior gate passes** (PRD §13).

## 6. Success criteria (what the orchestrator judges)

A piece is successful when **all** hold:
1. Acceptance criteria from its PRD task/EARS requirement are met.
2. `swift build && swift test` green (CI, and locally where CLT allows).
3. `/simplify` applied; `/code-review` surfaces no unaddressed correctness issue.
4. `security-auditor` passes (Constitution §1).
5. New public API has a design note + doc-comments; provenance recorded where cloud is touched.

If any fail, the orchestrator reopens the piece with the **specific** gap, not a vague
"redo," and the loop recurses.

## 7. Realizing this as a Workflow (when we kick off)

The loop maps directly onto the `Workflow` tool — pipeline the pieces, each through
architect → builder(+/simplify) → qa, with security-auditor and orchestrator-judge as
verify stages, looping until clean. A sketch lives in
[scaffold-plan.md](scaffold-plan.md) §6. The orchestrator may also run the loop turn-by-turn
via the `Agent` tool for tighter human-in-the-loop control. Either way, **this document is
the contract** the workflow encodes.

## 8. Standing constraints (apply to every agent)

- The Security & Privacy Constitution ([CLAUDE.md §1](../CLAUDE.md)) is inviolable.
- TDD where practical; green build/test before "done."
- App-target work is **blocked until Xcode is installed**; package work proceeds.
- Keep the repo current: small commits, clear messages, update checklists as gates pass.
- Never wire or invoke a Salesforce/Altify write path. `security-auditor` has veto.
