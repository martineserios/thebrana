# Stale-task lifecycle policy (t-2743)

Status: **implementation in progress (t-2774).** This document resolves
the design questions the task's own context flagged. The park-mechanism
decision (§1) is formalized in
[ADR-078](../decisions/ADR-078-stale-task-park-via-tag.md).

## Problem

`stale_tasks()` (`brana-core/src/tasks/query.rs`) already exists and does
exactly what its name says — returns pending task/subtask items older than
a threshold, sorted oldest-first. Nothing consumes it. A 2026-08-12 audit
found the consequence: 407 tasks pending >30 days (52% of all pending),
including 1 P0 and 19 P1s, while the backlog grows roughly 2.7x faster than
it drains (+383 created / -143 completed per month, per the same audit).
Staleness is measurable but has no lifecycle — a task can sit unresolved
indefinitely with no signal beyond a manual `brana backlog stale` query.

## Design questions (resolved)

### 1. Park mechanism: tag-based, not a new status

`classify()` (`brana-core/src/tasks/query.rs`) already derives a synthetic
**`"parked"`** display state from `tags: [..., "parked"]` — it is not a
`status` enum value, and `validate_status` never needs to know about it.
`by_state` in `compute_stats` already buckets tasks this way today.

**Decision: reuse the existing tag convention, do not introduce a new
`status` value or a new field.** Parking a task means:

```
brana backlog set <id> tags +parked
```

This is deliberately **reversible and non-destructive** — `status` stays
whatever it was (`pending`), `parked` is additive metadata. Unparking is
`tags -parked`. No new enum, no migration, no write-path changes to
`validate_status`/`set_field` at all — the mechanism already exists and is
already tested (`stats["by_state"]["parked"]` assertions in
`tasks/mod.rs`'s test suite). The only new code is the *automation* that
applies/removes the tag on a schedule (§3).

Rejected alternative: a new `status: "parked"` value. This would require
`validate_status` changes, `classify()` changes to stop deriving `"parked"`
from the tag (or maintain two parallel signals), and touches the same
class of "two ways to say the same thing" drift this project has hit
repeatedly (ADR-065's Consequences section, the `stream`/`kind` drift
history in `task-convention.md`). The tag mechanism is already the single
source of truth for this state — extend it, don't duplicate it.

### 2. Reversibility

Fully reversible by construction (§1) — parking only adds a tag. The
scheduled job (§3) must still log every action it takes (task id, action,
reason, timestamp) to a durable location so a human can audit and revert
in bulk if a run misfires. Proposed: append one line per action to
`system/state/stale-lifecycle-log.jsonl` (same pattern as other scheduler
jobs' state files under `system/state/`), not `tasks.json` itself — keeps
the audit trail out of the file every read/write path already contends
for.

### 3. Escalation surface: session-start injection, not focus or weekly-only

Three candidate surfaces were named in the original task: `backlog_focus`
injection, session-start injection, weekly review. Decision: **session-start
surfacing for P0/P1 only; weekly review gets the aggregate; `backlog_focus`
is untouched.**

Reasoning:
- `backlog_focus` already has a job (epic-scoped + P0/P1 overflow ranking,
  t-2314/t-2765) and is invoked on demand, not proactively — stale P0/P1s
  would only surface if someone happens to run focus, which is exactly the
  passive-discovery failure mode this policy exists to fix.
- Session-start is where `/brana:backlog start`, `/brana:sitrep`, and the
  statusline already inject state proactively (context-budget.md governs
  this surface's size explicitly — relevant, see §5). A single-line count
  ("⚠ 1 P0 + 19 P1 tasks stale >Nd — `brana backlog stale --priority P0,P1`")
  is cheap and matches the existing pattern of terse proactive warnings
  (e.g. the readiness-check soft-warns in `build/phases/load.md`).
- Weekly review (`/brana:review weekly`) is the natural home for the
  aggregate intake-vs-drain delta (§4c) — it already runs on a cadence and
  already reports numbers, not just flags.

Stale P2/P3 tasks are **not** escalated anywhere proactively — they're
handled entirely by the auto-park job (§4a), silently, since by definition
nobody has been acting on them and surfacing them would just be more noise
on top of the noise this policy exists to reduce.

### 4. Scheduled job shape

One `brana ops` job (wired the same way as existing jobs in
`system/scheduler/scheduler.template.json` — `command` type, `haiku`-tier
if it ends up needing any judgment, but this is fully mechanical so a
plain shell/CLI command needs no model at all), proposed name
`stale-lifecycle`, weekly cadence (staleness doesn't change meaningfully
day to day; matches the existing jobs' cadence style).

**(a) Auto-park P2/P3.** `brana backlog query --status pending --priority
P2,P3` piped through `stale_tasks()`'s threshold (default 90d, per the
task's own proposal — longer than the 60d default `backlog-reconcile.sh`
uses for its P3 bulk-cancel, since parking is non-destructive and can
afford a longer runway than cancellation) → `tags +parked` on each match,
skip if already parked. Never touches P0/P1 (escalates instead, §4b)
or epic-node/milestone/phase task types (only `task`/`subtask`, matching
`stale_tasks()`'s own type filter).

**(b) Escalate stale P0/P1.** No tag mutation — P0/P1 staleness is a
signal, not a state to reversibly set. The job just computes the count and
writes it where session-start can read it cheaply (a small JSON/count file
under `system/state/`, not a live query on every session start — session
start is exactly the surface context-budget.md says to protect).

**(c) Weekly intake-vs-drain report.** Count of tasks created vs. completed
in the trailing 7/30 days (the audit's own +383/-143 monthly framing).
Written to the job's own log; surfaced by `/brana:review weekly` reading
that log, not by the job posting anywhere itself — keeps the job a pure
data-producer, consistent with every other scheduler job's shape.

### 5. Context-budget interaction

The session-start escalation (§4b/§3) must be a single line, gated behind
"only if count > 0" (no line at all when clean — matches the readiness-check
soft-warn pattern). This is the one place this feature touches the
always-loaded-adjacent surface `context-budget.md` governs; everything
else (the park action, the weekly report) is pull-based (`brana backlog
stale`, `/brana:review weekly`), not push, and therefore outside that
budget's concern entirely.

### 6. Epic `wip_limit` — ships separately, not bundled

ADR-065 promised an epic `wip_limit` (default 10, applied at read time) —
already implemented as `check_epic_wip_cap()` (advisory warn-not-block,
per ADR-065 D4) but has no relationship to task-level staleness; an epic
being over its WIP cap and a task being stale are different failure modes
(too much *concurrent* work vs. one thing sitting *untouched*). Bundling
them into one feature would conflate two policies with different owners,
different signals, and different remedies. Ships as its own task if/when
someone wants gate enforcement for it (see t-2744, a related but distinct
spec).

## Out of scope (this spec, and the follow-up implementation task)

- Any change to `validate_status`, `classify()`, or the tag-vocabulary
  validators — the tag mechanism is reused as-is.
- Auto-cancelling anything — that's `backlog-reconcile.sh`'s job (manual,
  human-triggered, already exists, already fixed for epic filtering in
  t-2765). This policy only parks (reversible) and escalates (informational).
- Retroactively parking the current 407 stale tasks — the job parks going
  forward; a one-time backfill (if wanted) is a separate, explicitly
  human-approved run, not something the scheduled job does on first
  activation (a job that silently bulk-tags 300+ live tasks the first time
  it runs is exactly the kind of surprise a scheduled job should never
  produce).

## Follow-up implementation task

File as a new task once this spec is reviewed: `brana ops` job wiring
(`system/scheduler/`), the state/log files under `system/state/`, the
session-start single-line surfacing, and the `/brana:review weekly` report
integration. Suggested effort: M (touches scheduler config, a new small
Rust or shell driver over the existing `stale_tasks()` primitive, and one
skill-phase-file edit for the session-start line) — TDD as normal once
that task starts.
