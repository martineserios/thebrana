---
depends_on:
  - docs/architecture/decisions/ADR-051-reminder-store-architecture.md
  - docs/ideas/async-close-design.md
informs:
  - docs/ideas/async-first-close.md
---
# Feature: Reminder System — Two-Layer Sources, Rust-Owned Store

**Date:** 2026-06-10
**Status:** shipped
**Tasks:** t-1962 (parent), t-1964 (ADR), t-1966 (CLI), t-1965 (wrapper), t-1967 (session-start), t-1968 (docs)
**ADR:** ADR-051

## Problem

The async-first close architecture defers learning extraction to a nightly cron. Deferred learnings — and any event a hook notices mid-session ("edited hooks 3×, run validate") — need to be held somewhere and surfaced later without blocking session close or session start. The original bash-jq store design was killed by adversarial review: concurrent jq read-modify-write from parallel CC sessions loses appends silently (last-writer-wins leaves valid JSON, so the loss is invisible by definition).

## Decision Record (frozen 2026-06-10)

> Do not modify after acceptance. See [ADR-051](../decisions/ADR-051-reminder-store-architecture.md) for full alternatives analysis.

**Context:** Reminders must be writable from any hook in real time and from batch cron jobs, on a machine where parallel CC sessions are daily reality. The stated catastrophic failure mode is "reminders silently lost."

**Decision:** Single store at `~/.claude/reminders.json` mutated only by the brana Rust CLI (`brana remind write/list/resolve/snooze`). Every mutation takes an exclusive advisory lock on a sidecar `reminders.json.lock` file, validates parse-before-write, and writes via same-directory temp file + atomic rename. Bash exposure is a marshalling-only wrapper (`write_reminder`); session-start reads with pure jq (stale-ok).

**Consequences:** The store is safe under parallel sessions; every future "remind me when X" idea is one hook + one `write_reminder` call; the wrapper could not ship before the CLI (sequential chain); Track 2 cron sources build on a proven store.

## Architecture

### Write path (single owner)

```
hooks ──> write_reminder() ──┐  (lib/remind.sh — marshalling only, no jq)
                             ├──> brana remind write ──> ~/.claude/reminders.json
nightly cron (Track 2) ──────┘     │
                                   ├── lock reminders.json.lock (advisory, exclusive)
                                   ├── parse-before-write (corrupt store → error, never clobbered)
                                   ├── dedup: dedup_key match → occurrences+1, last_seen;
                                   │         occurrences ≥ 3 bumps medium → high
                                   └── mktemp in store dir + atomic rename
```

Why a sidecar lock file: atomic rename replaces the store's inode, so a lock held on the store itself would not serialize the next writer. The `.lock` file is never replaced.

### Read paths (separated, ADR-051 §3)

| Path | Mechanism | Writes? | Budget |
|------|-----------|---------|--------|
| `session-start.sh` | pure jq count, `[ -s ]` guarded | never | ~2ms (<50ms budget) |
| `brana remind list` | Rust, under write lock | **only** transition persister | interactive |

`list` computes AND persists lifecycle transitions: snooze expiry (snoozed → pending) and 30-day pending → expired. The session-start count may therefore be slightly stale — accepted.

### Lifecycle

```
pending ──resolve──> resolved          (terminal)
pending ──snooze──>  snoozed ──expiry──> pending     (on next list)
pending ──30 days──> expired           (on next list; surfaces in weekly digest)
```

### Two-layer sources

- **Layer 1 (event-based):** any hook sources `system/hooks/lib/remind.sh` and calls `write_reminder` in real time.
- **Layer 2 (batch):** the nightly extraction cron (async-close Track 2, not yet built) writes the four batch sources: large-pattern routing, errata accumulation, deferred doc updates, stale-queue self-monitoring.

### Schema v1 and evolution rules

`{version: 1, reminders: [{id, text, action?, priority, status, created, last_seen, occurrences, dedup_key?, project?, tags, snoozed_until?, resolved_at?}]}`. Binding rules: no `deny_unknown_fields`; every post-v1 field is `Option<T>`/`#[serde(default)]`; version is checked via `serde_json::Value` before strict parse; ids are random (`r-` + 8 random bytes hex), never content-derived; timestamps UTC RFC3339.

## Implementation

| Component | File | Tests |
|-----------|------|-------|
| Store logic | `system/cli/rust/crates/brana-core/src/remind.rs` | 14 unit incl. 8-writer race test |
| CLI surface | `system/cli/rust/crates/brana-cli/src/commands/remind.rs` | 6 integration (`remind_smoke.rs`) |
| Hook wrapper | `system/hooks/lib/remind.sh` | `tests/test-remind-lib.sh` (13) |
| Session-start surfacing | `system/hooks/session-start.sh` (`[Reminders]` section) | `tests/test-reminder-count.sh` (11) |

The concurrent-write race test (`concurrent_writers_both_appends_survive`) is the test this feature exists for: without the lock, parallel writers silently lose appends — see pattern memory `silent-loss-needs-lock-not-watchdog`.

## Usage

See the [user guide](../../guide/features/reminder-system.md).
