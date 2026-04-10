---
produced_by: docs/research/2026-04-08-url-batch-findings.md
depends_on:
  - docs/architecture/features/build-loop-redesign.md
---
# Feature: Checkpoint/Resume for Skill Procedures

**Date:** 2026-04-10
**Status:** shipped
**Task:** t-1108

## Problem

`/brana:build` has no durability story. A crash, context reset, or accidental session close at phase 5 of 6 means restarting from phase 1 — repeating LOAD, CLASSIFY, SPECIFY, and DECOMPOSE before getting back to where the work was. For Medium/Large builds (the ones that take long enough to be at risk), this is a significant pain.

The Kitaru project (`@Checkpoint`/`@Flow` decorators, Cluster C of the 2026-04-08 URL batch research) demonstrated the crispest solution: a minimal JSONL step log written at phase boundaries. Each entry has an idempotent step ID. On resume, the runner reads the log, skips completed steps, and picks up where it left off.

## Decision Record (frozen 2026-04-10)

> Do not modify after acceptance.

**Context:** Brana's build procedure already has CC Tasks for compression resilience within a session (Step 0b). But CC Tasks don't survive session close — they're session-scoped. A separate durable file is needed to survive across sessions. The `~/.claude/run-state/` directory is the right place: it's outside the repo (no git noise), user-local (not shared), and named by task ID (collision-free).

The Kitaru pattern maps cleanly:
- `@Checkpoint` → blockquote instruction at the end of each major step
- `@Flow` → Step 0c RESUME CHECK at skill start
- Idempotent step IDs → use the existing step names (LOAD, CLASSIFY, SPECIFY, etc.)
- Log format → JSONL, one line per completed step

**Decision:**
1. Add `Step 0c: RESUME CHECK` to `system/procedures/build.md` — reads `~/.claude/run-state/{task_id}.jsonl` on start, fast-forwards past completed steps
2. Add `☑ Checkpoint` blockquotes at the end of every major step in every strategy
3. Add cleanup instruction in CLOSE — deletes the run-state file on successful completion
4. Gate: M+ builds with a task_id only. Trivial/Small builds skip checkpoints entirely.

**Consequences:**
- Easier: crashes no longer mean full restarts for M+ builds
- Easier: mid-run observability — the run-state file shows exactly where the build is
- Easier: pairs naturally with auto-learning (EXTRACT can run at each boundary, not just close)
- Harder: none — the mechanism is additive and optional; it degrades gracefully (missing file = fresh start)
- Risk: stale run-state file from an abandoned build could cause unexpected fast-forwarding — mitigated by CLOSE cleanup and the user seeing the "⏩ Resuming" banner before skipping

## Constraints

- Must not block builds with no task_id (freeform descriptions)
- Must not activate for Trivial/Small builds (overhead not worth it)
- Must degrade gracefully when `~/.claude/run-state/` doesn't exist (mkdir -p on first write)
- CLOSE cleanup must be unconditional — no stale files left behind

## Scope (v1)

### Step markers added

All strategies:
- Shared: LOAD, CLASSIFY, EXTRACT, EVALUATE, PERSIST
- Feature/Greenfield/Migration: SPECIFY, DECOMPOSE, BUILD
- Bug Fix: REPRODUCE, DIAGNOSE, FIX
- Refactor: SPECIFY (light), VERIFY-COVERAGE, BUILD
- Spike: QUESTION, EXPERIMENT
- Investigation: SYMPTOMS, INVESTIGATE

### Run-state file format

```
~/.claude/run-state/{task_id}.jsonl
```

One line per completed step:
```json
{"step":"LOAD","completed":"2026-04-10T14:30:00Z","task_id":"t-1108"}
{"step":"CLASSIFY","completed":"2026-04-10T14:32:00Z","task_id":"t-1108"}
{"step":"SPECIFY","completed":"2026-04-10T14:45:00Z","task_id":"t-1108"}
```

### Resume flow

1. Read file: `cat ~/.claude/run-state/{task_id}.jsonl 2>/dev/null`
2. Parse step names from each line
3. Display: "⏩ Resuming t-1108 from checkpoint. Completed: LOAD, CLASSIFY, SPECIFY. Starting at DECOMPOSE."
4. Fast-forward: skip all steps in the completed list
5. Update CC Task registry to mark skipped steps as completed

### Cleanup

On CLOSE (successful completion only):
```bash
rm -f ~/.claude/run-state/{task_id}.jsonl
```

Abandoned builds leave a file — this is intentional. The user can manually delete `~/.claude/run-state/` to reset.

## Design

**Location:** `system/procedures/build.md` — procedure-level change, no CLI code needed.

**Pattern used:** Blockquote callouts (`> **☑ Checkpoint — STEP_NAME**`) visually distinct from procedure body. The `>` prefix keeps them from blending into the step instructions. The `☑` icon makes them scannable.

**Checkpoint write command:**
```bash
mkdir -p ~/.claude/run-state
printf '{"step":"LOAD","completed":"%s","task_id":"%s"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" \
  >> ~/.claude/run-state/{task_id}.jsonl
```

## Documentation Plan

- [x] **Tech doc** — this file
- [x] **User guide** — `docs/guide/features/checkpoint-resume.md`

## Challenger findings

Not formally reviewed (small, additive, no architectural risk). Key concern self-identified: stale run-state from abandoned builds. Mitigated by CLOSE cleanup + visible "⏩ Resuming" banner.
