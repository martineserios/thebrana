---
title: "Reminders, Scheduling, Tasks — Integral Design Model"
status: draft
created: 2026-06-12
---

# Reminders, Scheduling, Tasks — Integral Design Model

> Brainstormed 2026-06-12. Exploring unified data model across three tightly coupled systems.

## Problem

Three systems exist but operate in isolation:

1. **Scheduler (ADR-002):** Systemd timers run jobs on fixed intervals. ~23 jobs in production (daily focus, feed polls, nightly extraction).
2. **Reminders (ADR-051/ADR-054):** Event-based and batch sources write to a Rust-owned store. Channels (Telegram, Desktop, Ntfy) dispatch via a scheduler job (t-1999 pending).
3. **Tasks (backlog):** ID, subject, status, priority, tags, context. No inherent timing or reminder integration.

**The coupling problem:** 
- A task can have a deadline or due date (captured vaguely in `context` field), but no formal link to a reminder.
- A reminder can mention a task (e.g., "t-1999 dispatch is blocked") but the store has no `task_id` field.
- Scheduler jobs are independent; a job that should create a reminder (e.g., "task X is due today") must hardcode it.
- Data flows between these systems are implicit — hidden in hook code, cron scripts, and field semantics.

## Proposed Solution

Design one unified model that formalizes:
1. **Temporal primitives:** what triggers an action (fixed schedule, task due date, reminder time, event)
2. **Data linkage:** explicit edges between reminders ↔ tasks ↔ jobs
3. **Lifecycle semantics:** how reminders relate to task completion, how dispatch outcome feeds back to visibility

**Core insight:** Task + Reminder + Scheduler Job are all instances of the same pattern: "something should happen at a specific time, with an action and a visibility model."

## Research Findings

- **Tight coupling is real:** t-1999 (dispatch job) blocks on t-2000 (spec), which doesn't exist yet because the spec needs to define the channel model. But channels are already part of ADR-054, so t-2000 is just docs. The blocker is artificial — rooted in missing clarity on how reminders relate to tasks.
  
- **Existing foundations are solid:** ADR-051 (Rust store + lock) solves concurrency; ADR-054 (Notify context) establishes channel abstraction; systemd (ADR-002) handles job timing. No major rewrites needed.

- **The gap:** No shared model of "what is due when" across all three systems. The scheduler knows "run job X at 02:00 daily." Reminders know "dispatch this reminder at time T to channels [C]." Tasks know "priority P, blocked by [tasks]." But there's no unified language that says "task X is due at time T and has a reminder that triggers dispatch to channels [C] at time T-1hour."

## Risks

1. **Over-design:** Unifying three systems might introduce unnecessary abstraction. Risk: create a meta-model that no one can reason about.
   - Mitigation: Start with concrete use cases (task due date → auto-create reminder, reminder dispatch fails → task context note), not abstract unification.

2. **Breaking changes:** Existing stores (reminders.json, notify-channels.json, tasks.json) must evolve without breaking parallel sessions.
   - Mitigation: ADR-051 §4 already established lenient schema evolution rules (Option<T>, serde defaults). Apply same rules here.

3. **Scope creep:** "Integral model" could balloon into calendar sync, external task systems, webhook triggers.
   - Mitigation: Define v1 scope narrowly (task due date field + reminder task_id + dispatch → task context update) and explicitly defer extensions as future channels.

## Direction analysis (2026-06-12 discussion)

Three options compared: **A** full unification (one ActionUnit entity — rejected: over-design, migration risk, obsoletes ADR-051/054), **B** edges + glue only (rejected: coupling stays tribal knowledge), **C** shared primitives with separate entities (chosen, then stress-tested).

**Why the entities stay separate:** task = work (open-ended), reminder = attention signal (fire once, human resolves), scheduler job = recurring process (never "done"). Three lifecycles; one entity would force every consumer to branch on kind.

### C after adversarial review — five fracture points and resolutions

1. **`due` semantics are typed, not uniform:** reminders carry *fire-at*; tasks carry *finish-by* (deadline) + lead-time policy for derived pings (e.g. T−1d). The shared part is the vocabulary and machinery, not the meaning.
2. **Compute, don't copy — RESOLVED incl. snooze semantics (follow-up round):** task-due pings are never materialized *ahead of dispatch*. The due-checker derives "what fires now" from live task state each run; at fire time the dispatch record IS a real reminder row (dedup_key `task:t-NNN:due` — ADR-051's dedup machinery already requires this). Snooze therefore needs zero new machinery: it operates on that row like any reminder. **Semantic firewall — two verbs, never conflated:** snooze the ping = per-user attention state in the reminder store, `due_date` untouched (snooze past deadline → refire framed as "overdue by N days"); move the deadline = explicit `brana backlog set t-NNN due_date`, project-scoped, never reachable via a snooze action. The row stores only timing + dedup + task_id — never message content; refires re-derive everything from live task state. **Stale-snooze rule (user decision 2026-06-12):** deadline moved while snoozed → one terminal informational refire ("deadline moved to {new date}; reminder closed") on the row's own `channels`, then expire — a snooze is a promise, never break it silently. Task completed/cancelled while snoozed → expire silently (you closed the loop yourself; notifying is noise).
3. **One-directional references:** `reminder.task_id` only (with existing `project` field — reminders are per-user, tasks per-project). Reverse lookup is a query (`brana remind list --task t-NNN`), never a stored back-edge. No cross-store transactions exist; don't pretend they do.
4. **Recurrence — RESOLVED (follow-up round):** recurrence is a trigger expression, not an entity. `recur: Option<String>` on the reminder (v1 keywords: `daily`, `weekly:mon`, `monthly:1`). The stored row is the *series*; `due` always holds next fire time; occurrences are never materialized (same "compute, don't copy" principle). On dispatch: set `dispatched_at`, advance `due` per `recur`. Unified eligibility predicate covers one-shot and recurring with no branching: `due ≤ now AND (dispatched_at null OR dispatched_at < due)` — the one-shot "never dispatch again" rule (ADR-054) is the degenerate case. Semantics: `resolve` = kill series (terminal); `snooze` = defer one occurrence; no per-occurrence acknowledgment. **Boundary rule:** executes code → scheduler job (ADR-002 monopoly); routes attention → reminder with recur. Deferred to post-v1: complex RRULEs, exception dates, per-occurrence done-tracking.
5. **Read-time consistency:** task cancelled/completed → linked reminders are skipped at list/dispatch time by checking live task status (same pattern as sitrep's stale-next[] filter). No write-time cascades across stores.

### Final adversarial sweep (system-level, 2026-06-12)

Second challenge round attacking the whole design rather than individual entities. Five findings:

1. **Foundation unproven (most serious):** the entire design layers on the dispatch loop, and t-1999 (the dispatch job) has zero operational hours — it's pending, blocked on a spec that doesn't exist. **Decision: staged iterative rollout** — each stage ships, soaks in production, and proves itself before the next layer starts (see Staged Rollout below). Early dispatch lessons get absorbed cheaply instead of invalidating finished upper layers.
2. **Lead-time policy had no home** — a per-user attention preference that would otherwise pollute the per-project task store. **Decision: per-priority defaults**, derived from a field tasks already have: P0 → T−3d + T−1d + T−0; P1 → T−1d + T−0; P2 and below (or no priority) → T−0 only. Zero new config, no boundary violation. Per-task `lead_time` override deferred to post-v1.
3. **Recurrence advancement bug (RESOLVED stamp on fracture #4 was premature):** advancing `due` from actual dispatch time accumulates drift; advancing from scheduled time risks a catch-up storm after downtime (3 missed days of a `daily` → 3 stale fires in one run). **Fix: advance from scheduled time, skip missed occurrences** — loop the advancement until `due > now`, fire at most once per run.
4. **Predicate needs a status guard:** snoozed rows must stay dispatchable; resolved/expired must not. Full eligibility: `status ∈ {pending, snoozed} AND due ≤ now AND (dispatched_at null OR dispatched_at < due)`.
5. **Who watches the watcher (accepted dependency, not solved here):** the attention system hangs off one scheduler job whose failure mode is silence — close-extraction failed silently for nights before today's fix. Mitigation lives outside this design: sitrep and session-start already surface failing scheduler jobs. Named, accepted.

## Staged Rollout (replaces earlier phase sketch)

Iterative: every stage ships something functional, soaks in production, and gates the next. ADR for the integral model written once, up front (DDD); each stage carries its own tests-first + spec/doc updates.

- **Stage 0 — Prove the pipe (dispatch MVP).** Write the dispatch spec (t-2000, unblocks t-1999), ship the dispatch scheduler job: read reminders.json, fire eligible one-shot pending reminders to channels, set `dispatched_at`. Predicate v0: `status = pending AND due ≤ now AND dispatched_at null`. **Spec requirements from challenger review (HIGH confidence):** (a) first-run backfill policy — the store holds ~66 pending reminders that would all fire on day one; mark pre-existing rows dispatched or send one digest; (b) bash orchestrates, only `brana remind` verbs mutate the store (ADR-051 Rust-owned lock — no direct JSON edits from the job); (c) flock around the dispatch pass (no double-fire from overlapping systemd runs); (d) dispatcher and due-checker are ONE job, one pass — no two jobs racing on the locked store; (e) `daily` recurs in local time, DST stance documented. *Gate: several days of real dispatches; failure modes (rate limits, auth expiry, double-fires) logged and absorbed.*
- **Stage 1 — Harden the loop.** Fold in Stage 0 lessons; make snooze/resolve round-trip through dispatch. Upgrade to the full predicate: `status ∈ {pending, snoozed} AND due ≤ now AND (dispatched_at null OR dispatched_at < due)`. *Gate: snooze → refire works in production.*
- **Stage 2 — Recurrence.** Add `recur: Option<String>` (v1 keywords: `daily`, `weekly:mon`, `monthly:1`). Advancement: from scheduled time, skip missed occurrences (advance until `due > now`), fire at most once per run. *Gate: a daily reminder runs correctly for a week, including one deliberate missed-day catch-up test.*
- **Stage 3 — Task linkage.** Add `due_date` to tasks and `task_id` to reminders (lenient schema per ADR-051 §4). Due-checker derives pings with per-priority lead times, materializes at dispatch (dedup_key `task:t-NNN:due`), skips closed tasks at read time. *Gate: a real task deadline produces the correct ping sequence end-to-end.*
- **Stage 4 — Full semantics + consolidation.** Stale-snooze terminal refire ("deadline moved", on the row's own channels, then expire; silent expire when task closed by user). Docs sweep + ADR finalization.

**Backlog planning — SCOPE DECISION (final challenge, 2026-06-12):** only **Stage 0 + the ADR** enter the backlog now. Rationale: the store holds ~66 unresolved reminders — the system is demand-side saturated; adding supply (task-due pings, recurrence) before dispatch runs and the existing backlog is triaged would be solving the wrong bottleneck. Stages 1–4 stay in this doc and enter the backlog only after Stage 0's soak gate proves demand. Backlog gravity is real — don't create tasks for unproven layers. Fold in the paused `/brana:backlog add "link reminders to tasks"` answers (feature, effort L, blocked_by t-1999/t-2000 → those ARE Stage 0); the linkage task itself is Stage 3 and stays out of the backlog for now.

## Engineering Disciplines (SHAPE, approved 2026-06-12)

- **DDD:** one ADR up front — "Integral temporal model: shared primitives, separate entities." Extends ADR-051/ADR-054, respects ADR-002's scheduler monopoly. Written before any implementation task.
- **TDD (per stage, tests first):** predicate eligibility table tests; recurrence advancement incl. missed-day catch-up; snooze round-trip through dispatch; ping derivation per priority (P0/P1/P2 lead times); read-time skip of closed tasks; stale-snooze terminal refire.
- **SDD:** t-2000 dispatch spec is the Stage 0 deliverable; `docs/architecture/features/reminder-system.md` updated at each stage that changes semantics.
- **Docs:** tech doc update (reminder-system.md — schema + semantics change: yes); user guide for `brana remind` recur/snooze verbs (yes — new user-facing behavior); `docs/guide/commands/index.md` only if CLI flags change; overview untouched (no system-level pattern shift).
- **Success criteria:** task deadlines produce correct attention signals end-to-end; recurrence and snooze behave honestly; no new daemon, no new entity, no store migration.
