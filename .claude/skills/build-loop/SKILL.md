---
name: build-loop
description: Run the PrepOS recursive build loop for one piece — architect → builder (TDD + /simplify) → qa → security-auditor → orchestrator judgment, recursing until the piece passes. Use when building or completing a PrepOS package/app piece, or when the user says "build the next piece", "run the build loop", or "complete <task>".
---

# PrepOS build loop

Execute one piece of PrepOS through the full recursive loop defined in
[docs/orchestrator.md](../../../docs/orchestrator.md) §2. Do not skip steps; the loop's
value is the recursion.

## Inputs
- The **piece** to build (a PRD §13 task or a subsystem, e.g. "P1-e bucketing decision
  engine"). If unspecified, pick the next undone piece in the current phase.

## Procedure

1. **Design** — ensure `docs/design-notes/<piece>.md` exists and matches the docs. If not,
   delegate to the `swift-architect` agent to write it. Freeze any shared protocols first.

2. **Build (TDD)** — delegate to `swift-builder`:
   - write failing tests from the design note's test list,
   - implement the minimum to pass,
   - `swift build` (+ `swift test` where the env allows; CLT uses a `main.swift` driver),
   - run **`/simplify`** on the new code, re-build/test.

3. **QA** — delegate to `qa-engineer`: verify acceptance criteria, run/extend tests, run
   **`/code-review`**, file precise defects.
   - Defects → back to step 2 (builder fixes). **Recurse until QA is clean.**

4. **Constitution gate** — delegate to `security-auditor`. A violation is a HARD STOP →
   back to step 2. The auditor has veto. **Recurse until it passes.**

5. **Judge** — the orchestrator judges the piece against its PRD acceptance criteria
   (orchestrator.md §6). Not satisfied → reopen with a *specific* gap → recurse. Satisfied →
   commit with a clear message and mark the piece DONE (Task tools + checklists).

## Parallelism
Independent pieces (different SPM targets, no shared deps) run as parallel builders — issue
multiple `Agent` calls in one message. Use git worktrees if files would overlap.

## Guardrails
- The Security & Privacy Constitution ([CLAUDE.md](../../../CLAUDE.md) §1) is inviolable.
- `swift build && swift test` green before "done."
- App-target pieces are blocked until Xcode is installed — sequence package work first.
- Keep the repo current; tick CLAUDE.md §6 and the PRD §13 box when a phase gate passes.
