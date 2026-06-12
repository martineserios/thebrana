---
depends_on:
  - docs/architecture/decisions/ADR-052-close-queue-architecture.md
  - docs/architecture/features/reminder-system.md
  - docs/ideas/async-close-design.md
informs:
  - docs/ideas/async-first-close.md
---
# Feature: Async-First Close — Instant Close, Nightly Extraction

**Date:** 2026-06-11
**Status:** shipped (Tracks 1+2; batch sources t-1976 pending)
**Tasks:** t-1970 (phase), t-1971 (ADR-052), t-1972 (queue CLI), t-1973 (close skill), t-1974 (cron), t-1975 (surfacing), t-1978 (classify extraction), t-1977 (docs)
**ADR:** ADR-052 (+ ADR-051 for the reminder store it routes into)

## Problem

The 17-step FULL close ritual (debrief agent + 5 parallel extraction passes) blocked session end for minutes, so it got skipped — and skipped closes lose learnings entirely. The signal worth keeping (errata, patterns, field notes from the session's diff) doesn't need to be extracted *at* close time; it needs to be extracted *reliably*.

## Decision Record (frozen 2026-06-11)

> Do not modify after acceptance. Full pins in [ADR-052](../decisions/ADR-052-close-queue-architecture.md).

**Context:** Close must finish in ~30 seconds and never lose a session's diff, on a machine where parallel sessions close concurrently. The challenger review of the plan (2026-06-10) produced 4 CRITICAL pins, all encoded in ADR-052.

**Decision:** Close becomes snapshot + queue + handoff (Track 1); a 2am systemd-timer cron runs one agy pass per queued snapshot and routes all learnings to the reminder store (Track 2); session start surfaces both the reminder count and the overnight summary. The in-session deep debrief survives only behind explicit `--full`.

**Consequences:** Close is no longer a ritual; extraction is a reliability problem owned by a cron with health reporting; learnings arrive as reviewable reminders instead of interactive gates.

## Architecture

```
close (~30s)                     02:00 cron                      next session start
────────────                     ──────────────────────────      ──────────────────
classify mode ────────────────┐  close-extraction.sh             [Reminders] N pending
  (close-classify.sh)         │    brana close-queue list        [Yesterday] M learnings
snapshot diff (≤500KB) ───────┤    agy -p per snapshot             extracted overnight
brana close-queue append ─────┤    validate JSON contract
template handoff              │    write_reminder per learning
brana session write           │    append daily-summary-{date}.md
done                          │    mark-processed / mark-failed
                              └──► retries, stale monitor, prune
```

### Close modes (Track 1, ADR-052 §5)

| Mode | Trigger | Queues? | Extraction | Propagation audit (ADR-056) |
|------|---------|---------|-----------|------------------------------|
| NANO | 1 commit, ≤5 non-code files | no | none (below threshold) | skipped |
| LIGHT | non-code spread | yes | inline scan at close | L1 inline; L3 nightly |
| INSTANT | auto: ≥2 commits or code/behavioral changes | yes | nightly cron | L1 inline; L2 in-session on `--finish`, else L3 nightly |
| FULL | explicit `--full` only | yes | in-session debrief agent | L1 + L2 in-session |

Every queued close carries `propagate: true` (fail-safe); a successful in-session L2 audit clears it via `brana close-queue mark-propagated` so the nightly L3 pass skips that entry.

Classification logic lives in `system/scripts/close-classify.sh` — the single source of truth executed by both the close gate and its test (t-1978; a replicated copy rotted silently once).

### Stores (both Rust-owned, ADR-051 pattern)

| Store | Owner | Lock |
|-------|-------|------|
| `~/.claude/close-queue.json` | `brana close-queue append/list/mark-processed/mark-failed/prune` | sidecar `close-queue.json.lock` |
| `~/.claude/reminders.json` | `brana remind write/list/resolve/snooze` | sidecar `reminders.json.lock` |

The cron touches the queue **only** through CLI subcommands — zero direct JSON reads — and re-reads per iteration, so a session closing mid-run cannot be dropped (challenger C4).

### Extraction contract (ADR-052 §6)

agy (Gemini Flash, Layer A — **provisional**, revisit after ~2 weeks of summary review) must return `{"learnings": [{type, size, title, body, confidence}]}`. Empty/malformed output or an unreachable binary → `mark-failed` (one retry per night, never partial writes, never silently processed); 3 strikes → high-priority failure reminder. All learnings route to reminders (LARGE→high, SMALL→low, dedup-keyed) — none auto-write to memory in v1; the human routes at review.

Entries flagged `propagate: true` additionally get a propagation pass (ADR-056): same validate-or-mark-failed discipline, output contract `{"gaps": [{category, title, evidence, proposed_fix}]}`, repo state read at cron time with post-close commits surfaced for already-resolved-gap suppression. Gaps route to reminders tagged `propagation` (dedup `prop:{project}:{slug}`).

### Failure surfacing

- Cron exits non-zero on any failure → `brana ops` health
- Entries unprocessed >3 days → stale-queue reminder (checked **before** processing, so a recovering run still reports the stall)
- Per-run log line: `close-extraction: processed=N failed=N stale=N`

## Implementation

| Component | File | Tests |
|-----------|------|-------|
| Queue store | `system/cli/rust/crates/brana-core/src/queue.rs` | 16 (incl. 2 race tests) |
| Queue CLI | `crates/brana-cli/src/commands/close_queue.rs` | 5 smoke |
| Mode classify | `system/scripts/close-classify.sh` | 32 (`tests/procedures/test-close-weight-adaptive.sh`) |
| Snapshot+queue | `system/scripts/close-snapshot.sh` | 16 |
| Extraction cron | `system/cron/close-extraction.sh` | 23 |
| Close skill | `system/skills/close/phases/gate-and-evidence.md` (Step 1b, INSTANT branch) | via classify tests |
| Surfacing | `system/hooks/session-start.sh` (`[Yesterday]` + `[Reminders]`) | 10 + 11 |
| Scheduler | `system/scheduler/scheduler.template.json` → `close-extraction` @ 02:00 | live one-shot verified |

## Deferred

- **t-1976** — errata-accumulation + doc-drift batch sources (P3; counter mechanism must be pinned first, and a week of real extraction data informs the design)
- **agy → claude -p swap** — fires only if the ADR-052 §6 revisit trigger trips (week-1 review reminder set for 2026-06-18)
- **session notes** — `session_notes_path` is in the schema, null in v1

## Usage

See the [user guide](../../guide/features/async-close.md).
