---
status: accepted
---
# ADR-044 — Initiative accumulator: cross-day session continuity

**Status:** Accepted  
**Date:** 2026-05-25  
**Blocked-by:** ADR-043 (session_labels), t-1461

## Context

`session-state.json` has a daily TTL — replaced on each new day's close. Multi-session work on the same initiative loses its cross-day arc: accomplishments, open next-actions, and learnings from prior sessions are invisible the next day.

Three-tier persistence model:

```
session-state.json               → daily TTL  (today only, replaced tomorrow)
session-initiatives/{slug}.json  → initiative TTL  (survives until initiative ships)
session-history.jsonl            → all-time log  (never pruned)
```

## Decision

Add `brana_core::session_initiative` module implementing `InitiativeAccumulator` — a JSON file per initiative that grows across sessions via read→merge→atomic-write on each close.

**Schema** (`~/.claude/projects/.../memory/session-initiatives/{slug}.json`):
- `accomplished[]`: all accomplished items across sessions, deduped by exact text.
- `next[]`: outstanding items carrying forward; Pass 1 pruning moves task_id-linked completed tasks to `resolved[]` at merge time.
- `resolved[]`: items moved out of next[] with `resolved_at`, `resolved_by`, optional `resolution` note.
- `learnings[]`: deduped by first 60 chars (char-boundary safe).
- `tasks_completed[]`: task IDs confirmed done.
- `session_labels[]`: all labels that contributed (uses ADR-043 field).
- `sessions_count`: audit counter.

**`initiative: Option<String>`** added to `SessionState` — populated by close.md Step 9c, read by sitrep.md Source 4b.

**CLI:** `brana session initiative <upsert|read|archive>` — thin wrapper around brana-core functions.

**Initiative detection at close (Step 9c, 3-tier cascade):**
1. Tier 2a: `brana backlog query --status in_progress` → collect `initiative` fields.
2. Tier 2c: branch name parsing as fallback.
3. Tier 3: `AskUserQuestion` when 0 or 2+ initiatives detected.

Tier 1 (backlog-start marker) deferred — Tier 2a is sufficient for common case.

## Invariants

- All fields `serde(default)` — old accumulator JSON without any field deserializes cleanly.
- `validate()` rejects empty slug and path-separator chars to prevent path traversal.
- Atomic write via temp+rename — same pattern as `write_state()`.
- `started_at` set only on first creation, `last_closed` overwrites every upsert.

## What's deferred

- **Pass 2 pruning** (LLM-mediated text-only next[] review) — procedure-level enhancement.
- **Tier 1 marker** (`brana backlog start` writes session-start marker) — separate task.
- **`brana backlog complete --initiative X`** — separate task.
- **File locking** for true-concurrent parallel closes — last-write-wins is acceptable; recoverable from `session-history.jsonl`.

## Consequences

- Each close adds ≤1 file write (the initiative accumulator), after the session-state write.
- Sitrep gains a new Source 4b that surfaces multi-session arc at session start.
- No breaking change to existing session-state.json consumers — `initiative` field is optional.
