---
depends_on:
  - docs/architecture/decisions/ADR-051-reminder-store-architecture.md
  - docs/architecture/decisions/ADR-054-reminder-delivery-channels.md
  - docs/architecture/decisions/ADR-071-scheduler-thin-layer-over-systemd.md
  - docs/architecture/decisions/ADR-002-tasks-as-data-layer.md
informs:
  - docs/ideas/drained/reminders-schedule-tasks-integral.md
status: accepted
---

# ADR-089: Integral Temporal Model — Shared Primitives, Separate Entities

**Date:** 2026-08-24
**Status:** Accepted
**Tasks:** t-2074 (this ADR), t-1999 (Stage 0 dispatch job, shipped), t-2000 (docs sweep, pending)
**Source:** Reminders/scheduler/tasks brainstorm 2026-06-12 (3 adversarial challenge rounds); consolidated 2026-08-24

## Context

Three systems exist but operate in isolation:

1. **Scheduler (ADR-071):** systemd timers run jobs on fixed intervals — recurring processes, never "done."
2. **Reminders (ADR-051/ADR-054):** event-based and batch sources write to a Rust-owned store; channels (Telegram, Desktop, Ntfy) dispatch via a scheduler job.
3. **Tasks (ADR-002, backlog):** id, subject, status, priority, tags, context — no inherent timing or reminder integration.

The coupling problem: a task's deadline lives only informally in `context`; a reminder can reference a task in prose but the store has no `task_id` field (until ADR-051's t-2116 addition); scheduler jobs that should raise a reminder ("task X is due today") would have to hardcode it. Data flow between the three is implicit — hidden in hook code, cron scripts, and field semantics.

**Core insight:** Task + Reminder + Scheduler Job are all instances of the same pattern — "something should happen at a specific time, with an action and a visibility model" — but the three lifecycles are genuinely different (work vs. attention vs. process), so unifying them into one entity would force every consumer to branch on kind. Three options were compared (full unification, edges-and-glue-only, shared primitives with separate entities); the third was chosen and stress-tested across two further adversarial rounds. Full option analysis and round-by-round resolution: [docs/ideas/drained/reminders-schedule-tasks-integral.md](../../ideas/drained/reminders-schedule-tasks-integral.md).

## Decision

### 1. Kind-split — three entities, one vocabulary

- **Task** (ADR-002) = work: open-ended, closes by human action, no inherent timing.
- **Reminder** (ADR-051/054) = attention signal: fires once (or once per recurrence occurrence), a human resolves it.
- **Scheduler job** (ADR-071) = recurring process: never "done," executes code on a fixed interval.

The entities stay separate. What's shared is the *machinery* for expressing "when," not a common base entity: `due` semantics, an eligibility predicate shape, and a compute-don't-copy discipline. A reminder's `due` is a fire-at instant; a task's deadline is a finish-by instant plus a lead-time policy for derived pings — the vocabulary and machinery are shared, the meaning is typed per entity, and no attempt is made to force them into one column.

### 2. Unified eligibility predicate

A single shape governs whether a due-driven entity should fire now:

```
status ∈ {pending, snoozed} AND due ≤ now AND (dispatched_at IS NULL OR dispatched_at < due)
```

The `status` guard exists so snoozed rows stay dispatchable while resolved/expired rows never re-fire. The one-shot "never dispatch again" rule already in ADR-054 §3 is the degenerate case of this predicate (recurrence absent). No branch is needed between one-shot and recurring reminders — advancing `due` on dispatch is what turns a fired one-shot into a spent one and a fired recurring reminder into its next occurrence.

### 3. Compute, don't copy — no ahead-of-time materialization

Task-due pings (Stage 3, not yet built) are never materialized ahead of dispatch. The due-checker derives "what fires now" from live state every run; at fire time, the dispatch record IS a real reminder row (`dedup_key: task:t-NNN:due`, reusing ADR-051's existing dedup machinery — no new mechanism). This keeps a single source of truth (live task state) and avoids a second copy of "when is this due" that can drift from the task record.

### 4. Snooze ≠ deadline — semantic firewall

Two verbs are never conflated:

- **Snooze the ping** — per-user attention state on the *reminder row*. The task's `due_date` is untouched. A snooze that expires past the deadline refires framed as "overdue by N days," never silently.
- **Move the deadline** — an explicit, project-scoped `brana backlog set t-NNN due_date ...`. Never reachable via a snooze action.

The reminder row stores only timing, dedup key, and `task_id` — never message content. Every refire re-derives its message from live task state (name, current status, current deadline) at fire time, per §3.

### 5. Stale-snooze terminal refire

If the deadline moves while a ping is snoozed, the row fires exactly once more — an informational terminal message ("deadline moved to {new date}; reminder closed") on the row's existing `channels` — then expires. A snooze is a promise; the design never breaks it silently by just vanishing the row. If instead the task is completed or cancelled while snoozed, the row expires silently: the user already closed the loop themselves, and notifying would be noise. Read-time consistency for the non-snoozed case follows the same principle: a cancelled/completed task's reminders are skipped at list/dispatch time by checking live task status (no write-time cascade across stores), the same pattern sitrep already uses for its stale-`next[]` filter.

### 6. Per-priority lead times (no new config surface)

Lead-time policy is a per-user attention preference; putting it in the per-project task store would be a boundary violation. Instead it derives entirely from a field tasks already have (`priority`), with zero new config:

| Priority | Lead times |
|---|---|
| P0 | T−3d, T−1d, T−0 |
| P1 | T−1d, T−0 |
| P2 and below / unset | T−0 only |

Per-task `lead_time` override is deferred to post-v1 (no proven need yet).

### 7. Recurrence as a trigger expression, not an entity

Recurrence is a field on the reminder (`recur: Option<String>`, v1 keywords: `daily`, `weekly:mon`, `monthly:1`), not a separate series entity. The stored row *is* the series; `due` always holds the next fire time; individual occurrences are never materialized, per §3's principle. On dispatch: set `dispatched_at`, advance `due` per `recur`.

**Advancement rule (skip-missed):** advance from *scheduled* time, not actual dispatch time — advancing from dispatch time accumulates drift, and advancing from scheduled time without a skip rule risks a catch-up storm after downtime (three missed days of a `daily` naively producing three stale fires in one run). The correct rule loops the advancement until `due > now`, firing at most once per run — missed occurrences are skipped, never queued.

**Boundary with the scheduler (ADR-071):** if the "when" is about running code, it belongs to a scheduler job (ADR-071's monopoly on recurring execution) — a recurring reminder never becomes an ad hoc way to schedule code. If the "when" is about routing a human's attention, it is a reminder with `recur` set, dispatched by the one due-checker job. `resolve` kills the whole series (terminal); `snooze` defers exactly one occurrence; there is no per-occurrence acknowledgment. Complex RRULEs, exception dates, and per-occurrence done-tracking are explicitly deferred past v1.

### 8. Staged, soak-gated rollout

The full design layers on the dispatch loop, which had zero operational hours when this decision was shaped. Rather than build all five layers before any of them run in production, each stage ships, soaks, and proves itself before the next begins:

- **Stage 0 — dispatch MVP.** Predicate v0: `status = pending AND due ≤ now AND dispatched_at IS NULL`. Shipped and merged (t-1999, 2026-07-22): reminder-dispatch scheduler job wired every 30 minutes, notify-channels registry created, first-run backfill handled, verified end-to-end in production.
- **Stage 1 — harden the loop.** Upgrade to the full predicate in §2 (adds the `status ∈ {pending, snoozed}` guard and the recurrence-shaped dispatched_at comparison); snooze/resolve round-trip through dispatch. Not yet started.
- **Stage 2 — recurrence.** §7's `recur` field and skip-missed advancement. Gate: a daily reminder runs correctly for a week including one deliberate missed-day catch-up test. Not yet started.
- **Stage 3 — task linkage.** `due_date` on tasks, per-priority lead times (§6) materializing pings at dispatch via `dedup_key: task:t-NNN:due` (§3). Gate: a real task deadline produces the correct ping sequence end-to-end. Not yet started.
- **Stage 4 — full semantics + consolidation.** Stale-snooze terminal refire (§5), docs sweep, ADR/feature-doc finalization. Not yet started.

Per the original scope decision (idea doc, 2026-06-12): only Stage 0 and this ADR entered the backlog at brainstorm time — Stages 1–4 stay documented in the idea doc and enter the backlog only when the prior stage's soak gate proves demand. Backlog gravity is real; tasks are not created for unproven layers. Stage 0 having since shipped and soaked does not retroactively backlog Stage 1 — that remains a deliberate follow-on decision, not an automatic unlock.

### 9. One-directional references, no cross-store transactions

`reminder.task_id` is the only link (plus the existing `project` field — reminders are per-user, tasks per-project). The reverse lookup (find a task's reminders) is a query (`brana remind list --task t-NNN`), never a stored back-edge. No cross-store transaction exists or is assumed anywhere in this model.

## Relationship to prior ADRs

- **Extends ADR-051** (store ownership, locking, schema evolution rules) and **ADR-054** (channels, dispatch semantics, the `due`/`channels`/`dispatched_at` fields) — this ADR does not change either; it names the cross-cutting predicate and lifecycle rules that both already implement for the reminder side, and states how the task side will eventually plug into the same machinery.
- **Respects ADR-071's scheduler monopoly** — recurring code execution is a scheduler job, never a new daemon and never something a reminder's `recur` field triggers directly (§7).
- **Respects ADR-002's JSON-data-layer discipline** — `due_date` on tasks (Stage 3) is a plain additive, backward-compatible optional field on `tasks.json`, following the same schema-evolution pattern ADR-002 §Consequences already establishes for `tags`/`context` and that ADR-051 §4 establishes for the reminder store.

## Consequences

- A single documented vocabulary (`due`, eligibility predicate, compute-don't-copy, snooze-firewall) now exists for anything that fires at a time — every future "something should happen at time T" idea composes from this ADR instead of re-deriving its own semantics.
- No new entity, no new daemon, no store migration — Stages 1–4 are additive changes to the existing reminder store and task schema, gated by ADR-051 §4's evolution rules.
- The staged rollout means most of this ADR's decisions (§2, §5, §6, §7 recurrence, §8 Stages 1–4) are not live yet — they are the accepted design for stages that have not shipped. Only Stage 0 (§8) is running in production as of this writing.
- Lead-time policy (§6) and the snooze/deadline firewall (§5) are load-bearing on the task side; when Stage 3 ships, `brana backlog set t-NNN due_date` becomes the only sanctioned way to move a deadline — any future UI or automation must not resurrect a "snooze the deadline" shortcut.

## Non-Actions

- No unification into a single "ActionUnit" entity (Option A, rejected at the direction-analysis stage).
- No per-task `lead_time` override in v1 (§6).
- No complex RRULEs, exception dates, or per-occurrence acknowledgment for recurring reminders (§7).
- No write-time cascade between stores — all cross-store consistency is read-time (§5, §9).
- No new daemon; no SQLite; no calendar integration (calendar sync remains deferred per ADR-054's own Non-Actions).

## Changelog

- 2026-08-24: Initial acceptance (t-2074), consolidating the 2026-06-12 brainstorm and its three challenge rounds. Written after Stage 0 (t-1999) had already shipped (2026-07-22) — the ADR intentionally documents Stage 0 as shipped rather than pretending it is still pending, since ADR-writing was delayed relative to the idea doc's original "written before any implementation" intent.
