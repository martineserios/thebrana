---
depends_on:
  - docs/ideas/async-close-design.md
  - docs/architecture/decisions/ADR-004-session-handoff-self-learning-loop.md
informs:
  - docs/ideas/async-first-close.md
status: accepted
---

# ADR-051: Reminder Store — Rust-Owned Writes, Two-Layer Sources

**Date:** 2026-06-10
**Status:** Accepted
**Tasks:** t-1962 (parent), t-1964 (this ADR), t-1966 (Rust CLI), t-1965 (shell wrapper), t-1967 (session-start surfacing), t-1968 (docs), t-2116 (task_id link + past-due surfacing)
**Source:** Async-first close brainstorm + t-1961/t-1963 research spikes; challenger review 2026-06-10 (verdict: RECONSIDER → write architecture flipped)

## Context

The async-first close architecture (docs/ideas/async-first-close.md) defers learning extraction to a nightly cron. Learnings that need human routing — large/novel patterns, accumulated errata, deferred doc updates — must be held somewhere and surfaced later without blocking session close or session start. Hooks also need a way to write event-based reminders in real time (e.g., "edited hooks 3× — run validate.sh").

The original design had a bash-jq write helper (`remind.sh`) doing read-modify-write on a shared JSON store with atomic rename and no locking, deferring `flock` "until corruption is observed."

Adversarial review killed that design with three CRITICAL findings sharing one root cause: **concurrent jq read-modify-write from parallel CC sessions loses writes silently.** Last-writer-wins on a full-file rewrite destroys the loser's append, and the surviving file is structurally valid JSON — so "upgrade when corruption is observed" can never fire; the loss is invisible by definition. The user runs parallel sessions daily, and the stated catastrophic failure mode is precisely "reminders silently lost."

## Decision

### 1. Single store, Rust-owned mutation

`~/.claude/reminders.json` (per-user, cross-project) is mutated **only** by the brana Rust CLI:

- `brana remind write --text … --action … --priority … [--dedup-key …] [--project …] [--tags …] [--task-id …]`
- `brana remind list` — the **only** path that computes AND persists state transitions (snooze expiry, 30-day pending→expired), under the write lock
- `brana remind resolve <id>` / `brana remind snooze <id> <dur>` (1d/3d/1w)

The Rust write path owns:
- **Advisory file lock** on the store for every mutation
- **Parse-before-write validation** — never replace the store with output derived from unparseable input
- **Atomic write** — temp file created via mktemp **in the store's directory** (`/tmp` is tmpfs here; cross-filesystem `mv` is copy+delete, not atomic)
- **Dedup** — `dedup_key` match → increment `occurrences`, update `last_seen`, no duplicate entry; `occurrences ≥ 3` auto-bumps `medium → high`

### 2. Shell wrapper is marshalling only

`system/hooks/lib/remind.sh` exposes `write_reminder` to hooks as a thin wrapper around `brana remind write`. No jq, no JSON mutation in bash. If the brana binary is missing: warn to stderr, exit 0 — hooks never block.

### 3. Read-path separation

`session-start.sh` surfaces the pending count with a **pure jq read** guarded by `[ -s file ]` — no Rust invocation (binary startup would blow the <50ms budget; same reason session-start already uses the brana-query fast path), no transition writes. The count may be slightly stale (can include technically-expired reminders) — accepted.

Additionally (t-2116), the session-start hook uses a second jq filter to find past-due pending reminders (`.status == "pending" && .dispatched_at == null && .due <= now && .task_id != null`) and surfaces them as task-linked action recommendations. For each match, one `brana backlog get` binary call looks up the task subject — acceptable because past-due linked reminders are rare (expected 0–3).

### 4. Schema and evolution rules

Store schema v1 per docs/ideas/async-close-design.md (lifecycle: pending → resolved / snoozed / expired). Binding implementation rules:

- No `#[serde(deny_unknown_fields)]` on store structs
- Every post-v1 field is `Option<T>` or `#[serde(default)]`
- Read path parses `version` from `serde_json::Value` before strict deserialization
- Reminder `id` is random (short uuid form), never content-derived (md5-of-text collides on same-second identical writes)
- All timestamps UTC RFC3339

**Post-v1 fields added under these rules:**

| Field | Type | Added | Purpose |
|-------|------|-------|---------|
| `due` | `Option<DateTime<Utc>>` | t-1997 | When to dispatch (ADR-054 §3) |
| `channels` | `Option<Vec<String>>` | t-1997 | Explicit delivery routing |
| `dispatched_at` | `Option<DateTime<Utc>>` | t-1997 | Idempotency marker |
| `task_id` | `Option<String>` | t-2116 | Links reminder to a backlog task; enables task-aware session-start surfacing |

### 5. Two-layer sources

- **Layer 1 (event-based):** any hook calls `write_reminder` in real time
- **Layer 2 (batch):** the nightly extraction cron (async-close Track 2, out of scope for t-1962) writes the four batch sources: large-pattern routing, errata accumulation, deferred doc updates, stale-queue self-monitoring

### 6. Test scope

TDD for t-1966 includes a **concurrent-write race test** (two writers, both appends survive) — not just CRUD unit tests. This is the test that encodes the reason this ADR exists.

## Alternatives considered

### Bash-jq write with hardening (flock + mktemp + exit-code checks)
Pro: no Rust dependency for hook writes; works before the CLI ships. Con: dedup logic (find-match-increment-or-append) is three chained jq operations on a mutable document called from arbitrary hook contexts — too fragile; and it duplicates mutation logic that Rust needs anyway for resolve/snooze. Rejected: hardening N shell writers is strictly worse than one owning binary.

### SQLite store
Pro: real transactions, no hand-rolled locking. Con: adds a runtime dependency to every hook context; jq-readability of the store from session-start dies; overkill for a file that holds tens of entries. Rejected for v1; revisit only if the store outgrows JSON.

### Defer locking until corruption observed (original design)
Rejected — self-contradictory: the failure mode (lost appends) leaves valid JSON, so the observation trigger can never fire. See pattern memory `silent-loss-needs-lock-not-watchdog`.

## Consequences

- The wrapper (t-1965) cannot ship before the CLI (t-1966) — the chain is sequential: ADR → CLI → wrapper → session-start → docs
- Hooks gain a one-line reminder primitive; every future "remind me when X" idea is a hook + one `write_reminder` call, no schema work
- The store is safe under the user's daily parallel-session reality
- Track 2 (cron batch sources) builds on a proven store with zero write-path work remaining
