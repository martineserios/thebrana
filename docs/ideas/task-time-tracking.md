---
title: Project time & cost tracking — active effort and calendar cycle time
status: draft
created: 2026-08-17
---
# Project time & cost tracking — active effort and calendar cycle time

> Brainstormed 2026-08-17. Reviewed by 3-worker adversarial challenge; all findings
> resolved below before backlog planning.

## Problem

There's no reliable way to answer two related but distinct questions about a project:

1. **"How much active Claude effort (time + tokens) went into this?"** — a cost/effort
   number.
2. **"How much real-world calendar time did the whole engagement take — from first quote
   or design work, through kickoff, to delivery?"** — a cycle-time number, relevant to
   pricing future proposals accurately.

Neither exists today:

- Tasks already have `started`/`completed` fields (task-convention.md), but they are
  **date-only** (no time-of-day) and only populated on **536 of 2,789 tasks (19%)** —
  nothing currently auto-writes them, and nothing captures a pre-task "quoting" phase.
- Waves (`{selector, contract, gate, status}`, per `project_wave-mechanics-vocabulary`)
  have **no time fields at all**.
- `build-cost-tracking.md` (t-648) designed a session-transcript-anchoring mechanism for
  per-build **token cost**, but it was never implemented, and covers effort only — not
  calendar cycle time, and not the pre-task quoting/design phase.
- "Project" isn't a first-class type in this backlog — it resolves as the nearest
  `parent` ancestor with `type:"epic"` (task-convention.md).

## Two metrics, one rollup

Both roll up through the same project (epic) hierarchy — never blended into one number.
A project can have 40 hours of active Claude effort spread across a 6-week calendar
cycle; both numbers matter together for pricing, and collapsing them would hide the
comparison that makes this useful.

**Explicitly out of scope for both metrics, this pass:** wave-level rollup. Waves
(`{selector, contract, gate, status}`) pull tasks across epics via selector — "time for
wave X" isn't answerable by a parent→epic rollup, and that's accepted for v1. Waves are
transient work queues, not durable project boundaries. A wave-level *view* (sum of a
wave's selector-matched tasks' Metric 1 totals) can be added later without changing the
core design — it's a read, not a new write path.

### Metric 1 — Active effort (Claude time + tokens)

**Scope.** Claude session time only. Mapping non-Claude manual effort (calls, browser
review, thinking time) stays out of scope, deferred as a separate future problem.
**Subagent/fork delegation is also explicitly excluded from v1's time sum** — a fork's
real work collapses to a single tool_use→tool_result turn pair in the parent transcript,
and the gap between those two timestamps would otherwise be swallowed by the idle cap
exactly like real idle time, silently under-reporting exactly the tasks built with heavy
delegation. Any task where delegation was used gets a `coverage: partial` flag rather
than a silently-wrong number. (Whether fork subagents share the parent's transcript file
or write their own is unverified — noted as an implementation-time check, not resolved
here; the exclusion holds either way for v1.)

**Atomic unit = task**, not wave. Partitioning into tasks lets you track time *per task*,
and because tasks already form a hierarchy (task → parent → epic), summing up the
hierarchy gives the whole-project total for free.

**Bracket model.** A task's total time is the sum of **all (start_ts, end_ts) sub-spans
ever recorded for that task_id**, potentially across many transcript files/sessions —
not a single START/CLOSE pair. This is what makes cross-session resumption (crash,
`/compact`, days-later resume) fall out cleanly: an old session's bracket end is simply
its last real turn's timestamp (the existing orphaned-bracket fallback), and resuming a
task in a new session just opens a fresh bracket for the same task_id. No special
resumption logic needed beyond "sum all brackets for this task_id."

**One open bracket per session, serialized.** LOAD refuses to open a new task's bracket
while one is already open in the same session — the current task must CLOSE first. This
matches how top-level work actually happens here: parallelism comes from spawning
subagents under one active task, not from flipping which task is "active" mid-session.
(This pairs with the fan-out exclusion above — since subagent time isn't summed into
Metric 1 anyway, there's no case where two *top-level* brackets need to be open at once.)

**Coverage boundary.** Only tasks executed via `/brana:build` get measured — `kind:
research/design/docs` tasks that never invoke `build.md` structurally show zero. Named
explicitly as a boundary of v1, not a bug to silently work around; extensible later by
adding the same marker pattern to other skills (`/brana:research`, `/brana:fix`, etc.)
if needed.

**Marker-writing applies to every task through `/brana:build`, regardless of effort
size** — decoupled from the *existing, unrelated* `~/.claude/run-state/{task_id}.jsonl`
resume-checkpoint mechanism, which is gated to M+ builds only (`load.md:212`) for a
different reason (checkpoint overhead isn't worth it for trivial tasks that finish before
ever needing to resume). Time-tracking markers are cheap appends and don't inherit that
gate — S-effort tasks get coverage too.

**Storage — new namespace, not a collision.** Markers write to
`$(git rev-parse --git-common-dir)/brana/time/<task_id>.jsonl`, atomically (temp-file +
rename, same pattern as `build-receipts.md`), with the executed subprocess's git
environment scrubbed (H2, same hazard `build-receipts.md` already documents:
`GIT_DIR`/`GIT_WORK_TREE`/`GIT_INDEX_FILE`/`GIT_OBJECT_DIRECTORY`/`GIT_COMMON_DIR`).

This is a **deliberate change from t-648's original proposal** of
`~/.claude/run-state/{task_id}.jsonl` — verified live: that path is already occupied by
the LOAD-checkpoint/CLOSE-delete mechanism above (`close.md:235` does `rm -f
~/.claude/run-state/{task_id}.jsonl` on successful close). Reusing it as-is would destroy
effort data before it could ever be aggregated. The two mechanisms now coexist as
separate files with separate lifecycles for the same `task_id` — resume-checkpoint state
(ephemeral, deleted on success) and time-tracking state (durable, aggregated at CLOSE) —
which is fine as long as they're not confused for one another, hence the new
`brana/time/` namespace rather than silent reuse.

**Measurement: turn-delta summation with a 15-minute idle cap, not bracket-endpoint
spans.** Validated against this brainstorm's own session transcript: the raw session
spanned 63.5 hours wall clock (open across a multi-day idle gap), but turn-to-turn deltas
capped at 15 minutes summed to 0.51 hours — the actual active time (124x difference). Of
262 sub-cap gaps, 239 were under 5 seconds and the largest legitimate gap was ~5 minutes.

**Re-validated 2026-08-17 (t-2920) against 5 additional real session transcripts** from
this project, spanning build, bug-fix, and research task kinds and ranging from 1.35h to
27.25h of naive wall-clock span (2,198–7,652 turns each):

| Session (truncated id) | Turns | Naive span | Capped active | Gaps >15min | Max sub-cap gap |
|---|---|---|---|---|---|
| cc81cf5d | 7,652 | 27.25h | 6.51h | 9 | 12.92min |
| deb2eb19 | 4,905 | 23.40h | 3.83h | 2 | 8.09min |
| f021c8b3 (bug/research) | 2,893 | 15.33h | 2.84h | 2 | 11.53min |
| e644471f | 4,372 | 2.65h | 2.59h | 1 | 12.29min |
| dccbeb3d | 2,198 | 1.35h | 1.29h | 1 | 8.81min |

**Findings:**
- Across all 15 over-cap gaps found in these 5 sessions, **every single one** was either
  (a) an overnight/multi-hour idle break between sessions, or (b) an `AskUserQuestion`
  tool call awaiting user input (4.2–84.1 minutes observed) — i.e. genuine non-active time
  that the cap is correctly designed to exclude.
- **Zero cases** of a blocking `Bash`/`Agent`/`Task` tool call (test suite, build,
  subagent spawn) exceeding ~5 minutes were found in any of the 5 sessions — the specific
  risk named in the original caveat (long blocking tool calls being wrongly capped as
  idle) did not materialize in this sample. Absence of evidence is not proof for the
  general case — no session sampled happened to include an extremely long single test/build
  run — but across build- and bug-fix-shaped sessions specifically, no near-miss occurred.
- The closest sub-cap (i.e. correctly-not-capped) gap across all 5 sessions was 12.92
  minutes — within ~2 minutes of the 15-min threshold. This is a mild residual-risk
  signal: a legitimately-engaged-but-slow turn (e.g. a long-running Bash command whose
  result is the very next transcript entry) could plausibly cross 15 minutes in a larger
  or slower build even though it wasn't observed here.

**Conclusion: 15-minute idle cap confirmed safe to lock into the ADR**, with one
documentation addition recommended for the ADR: explicitly note that `AskUserQuestion`
waits are an expected source of long (sometimes 60-90+ minute) gaps that the cap will
correctly exclude — so a future reviewer doesn't mistake a large `AskUserQuestion` gap
for a tracking bug. No change to the 15-minute constant itself is warranted by this
re-validation.

**Aggregation timing: synchronous at CLOSE**, inheriting t-648's pattern exactly — the
computed number is stored, not a pointer into the transcript, so transcript
retention/rotation is never a dependency for historical totals.

**Output requirement — no bare numbers.** Every query surface (`brana backlog get
--field time_spent`, a `brana time` rollup) must emit a coverage annotation alongside the
figure — e.g. "40.2h across 6/7 tracked tasks, 1 flagged partial (delegation used), idle-
cap applied to 14 gaps" — never a bare `time_spent: 40.2h`. Given the stated pricing use
case, a bare number invites exactly the "precision masquerading as accuracy" trap. **A
shadow-validation period (compute silently for several weeks, compare against manual
estimates) is required before this number is wired into any real client quote or
invoice** — same pattern as this project's own `feedback_validate-loop-before-platform`
memory.

### Metric 2 — Real-world elapsed time (quote → kickoff → delivery)

- **Applies to all projects uniformly** — not just client/venture engagements. Internal
  or infra epics simply leave the milestone fields empty.
- **Source = explicit milestone fields, with derived signals as fallback.** Three
  timestamps on the epic/project task: `quote_started`, `kickoff_date`, `delivered_date`.
  - `kickoff_date` fallback → timestamp of the epic's first child task moving to
    `in_progress` (or first branch cut under the epic's slug).
  - `delivered_date` fallback → timestamp of the last child task's completion, or a
    ship/merge-to-main event tagged with the epic.
  - `quote_started` fallback → the **epic task's own creation timestamp**, as a weak,
    explicitly-approximate proxy (better than a permanently-null field with no reminder
    mechanism) — always surfaced with an "approximate — quoting likely started earlier"
    annotation, never presented as precise. True manual entry (an explicit `quote_started`
    set by the user) always overrides the proxy when present.
- **No relationship to the legacy `started`/`completed` fields.** These new fields are
  additive and independent — no backfill, no authority conflict, since they measure
  different things (a coarse date-only lifecycle marker vs. precise milestone timestamps).
- **This is deliberately NOT the same clock as Metric 1** — see "Two metrics, one
  rollup" above.

## Research findings — validated against a live transcript

Checked against this brainstorm's own session transcript
(`~/.claude/projects/-home-martineserios-enter-thebrana-thebrana/da172d34-*.jsonl`):

- **Every entry carries a per-turn ISO8601 UTC timestamp with millisecond precision**
  (`"timestamp": "2026-08-14T22:42:23.518Z"`), independent of the `message.usage` block
  `build-cost-tracking.md` already reads. Trivial to parse and diff.
- **The overnight-drift risk is not hypothetical — it happened in this very session.**
  Naive `close_ts - start_ts` span math: **63.46 hours**. Turn-delta summation with a
  15-minute idle cap: **0.51 hours** — a 124x difference.
- **A 15-minute idle cap is safe on this session, not aggressive** — but see the
  re-validation requirement above; this one data point is not enough to lock the constant
  in for coding-shaped sessions.

## Challenger review — 3-worker adversarial, 2026-08-17

All findings from the M+ governance-required challenger pass, and how each was resolved.
Confidence: **HIGH** = ≥2 of 3 workers independently converged (or directly verified
against source); otherwise single-worker.

| # | Finding | Confidence | Resolution |
|---|---|---|---|
| 1 | Storage path drift: t-648 said `~/.claude/run-state`, doc silently said `git-common-dir` | HIGH (2 workers) | New `brana/time/` namespace under git-common-dir; see Metric 1 storage section |
| 2 | `~/.claude/run-state/{task_id}.jsonl` already live (LOAD-checkpoint, CLOSE-deletes) — **verified directly against source** (`load.md:212`, `close.md:235`) | Verified | Confirms #1's resolution was necessary, not optional |
| 3 | Subagent/fork fan-out invisible to Metric 1 | HIGH (2 workers) | Excluded from v1 sum; `coverage: partial` flag |
| 4 | Concurrent/interleaved same-session multi-task attribution undefined | HIGH (2 workers) | Serialized — one open bracket per session |
| 5 | Existing marker precedent is M+-only → S-effort structurally uncovered | Verified against source | Time-tracking markers decoupled from the M+ gate, apply to all effort sizes |
| 6 | 15-min idle cap curve-fit to n=1 atypical session | HIGH (2 workers) | Re-validated 2026-08-17 (t-2920) against 5 real build/bug/research sessions; cap confirmed safe, see Metric 1 re-validation block |
| 7 | M+ discipline task graph not yet enumerated | HIGH (2 workers) | Resolved at backlog-planning time (below), not idea-doc level |
| 8 | No coverage/confidence signal at output layer, despite pricing use case | Single-worker, high-value | Mandatory coverage annotation + shadow-validation period before quote use |
| 9 | Cross-session/multi-day bracket-stitching undefined | Single-worker, high-value | Many-sub-spans-per-task_id bracket model (see above) |
| 10 | Atomic-write requirement named but not scheduled as its own deliverable/test | Single-worker | Carried into Next Steps as an explicit line item, not a parenthetical |
| 11 | H2 (git-env scrubbing) unmentioned for the transcript-reading step | Single-worker | Explicitly required, same as build-receipts |
| 12 | CLOSE-step latency budget shared with build-receipts `mint`, uncoordinated | Single-worker | Noted in ADR as a combined budget to track against K2 |
| 13 | `quote_started`'s "no safe fallback" too aggressive | Single-worker | Epic-creation-timestamp proxy added, always flagged approximate |
| 14 | Aggregation timing (sync at CLOSE vs. lazy query-time) unstated | Single-worker | Synchronous at CLOSE, inheriting t-648's pattern |
| 15 | `kind:research/design/docs` tasks never touch `build.md` → structural zero | Single-worker | Named as v1 coverage boundary, extensible later |
| 16 | Waves orthogonal to parent/epic rollup | Single-worker (user-relevant) | Confirmed out of scope for v1, future read-only view possible |
| 17 | Relationship to legacy `started`/`completed` fields undefined | Single-worker | Additive, independent, no backfill |
| 18 | Prompt-cache sharing across forks risks token-cost double-counting when folding in t-648 | Single-worker, minor | Footnote for the ADR; not blocking since forks are excluded from v1 anyway (#3) |

## Risks (post-resolution)

**Primary risk resolved 2026-08-17 (t-2920):** the 15-minute idle cap was re-validated
against 5 additional real session transcripts spanning build/bug-fix/research kinds — see
the re-validation block under Metric 1 above. Confirmed safe; no constant change needed.
Residual: the closest sub-cap gap observed was 12.92 minutes, so a legitimately-engaged
turn could plausibly cross 15 minutes in a larger/slower session than any sampled here —
worth a passive watch after Metric 1 ships, not a blocker.

**Secondary: `quote_started` will still be under-entered even with the creation-timestamp
proxy**, since the proxy is explicitly weak. A lightweight reminder mechanism (e.g. a
prompt at `/brana:brainstorm` or `/brana:backlog add` time when a new client engagement is
detected) is a good follow-up but not core scope.

**Tertiary (deferred, named in the original pre-mortem): coverage rot** if
marker-writing is later dropped from `build.md` without anyone noticing. A periodic
coverage-percentage check (same shape as the existing stale-task check) is the mitigation,
filed as follow-up, not core scope.

## Second-order effects

- **Fold t-648 (build-cost-tracking) into this design, on the new storage path** → 1st
  order: cost and duration share one marker mechanism instead of two competing efforts →
  2nd order: any future addition to what's measured only needs to be added once.
- **Marker-writing lives inside `build.md`'s LOAD/CLOSE steps, decoupled from the M+
  gate** → 1st order: every code task gets brackets automatically, all effort sizes → 2nd
  order (risk, confirmed non-obvious via challenger review): concurrent worktree sessions
  writing to shared marker state need atomic writes — not optional, given this repo's
  hard rule on concurrent worktrees.
- **Metric 2's derived fallbacks (kickoff/delivery) reuse existing task lifecycle
  events** → 1st order: no new instrumentation needed for those two fields → 2nd order:
  `quote_started` stands out as the one field with no strong safety net, reinforcing why
  it needs its own reminder mechanism as a follow-up.

## Next steps (M+ discipline task graph)

1. **ADR** (blocks all implementation tasks below): fold t-648 into this design on the
   `brana/time/` storage path; record the many-sub-spans bracket model, the serialized-
   one-bracket-per-session rule, the fan-out exclusion for v1, the M+-gate decoupling,
   the turn-delta/idle-cap measurement method (re-validated, see below), and the atomic-
   write + H2 requirements.
2. **Idle-cap re-validation — DONE (t-2920, 2026-08-17):** checked the 15-minute
   threshold against 5 real sessions spanning build/bug/research kinds. Confirmed safe;
   see the re-validation block under Metric 1 above.
3. **Tests before implementation — DONE (t-2921, 2026-08-17):** turn-delta summation with
   idle-gap capping (including a synthetic overnight-gap case); many-sub-spans rollup
   across multiple transcript files for one task_id; serialized-bracket rejection,
   redesigned per-worktree during SPECIFY (second START while one is open in the same
   worktree, sequential AND genuinely concurrent); atomic concurrent-write stress test
   (distinct-`task_id` and same-`task_id` variants, no corruption/loss); coverage-
   annotation output shape. See `docs/architecture/features/time-tracking-metric-1.md`.
4. **Implementation — Metric 1 — DONE (t-2922, 2026-08-18):** START/CLOSE marker writes
   wired into `build.md`'s LOAD/CLOSE steps (`system/skills/build/phases/load.md`/
   `close.md`), keyed by `task_id`, atomic writes to
   `$(git rev-parse --git-common-dir)/brana/time/<task_id>.jsonl`, git-env scrubbed.
   `brana time start|close` in `brana-cli`/`brana-core`; 25/25 tests green.
5. **Implementation — Metric 2** (can start independently, no dependency on 1-4): add
   `quote_started`/`kickoff_date`/`delivered_date` fields to the epic/task schema, plus
   derived-fallback logic for `kickoff_date`, `delivered_date`, and the approximate
   `quote_started` proxy.
6. **Aggregation + query command** (blocked_by 4 and 5): per-task active time via
   turn-delta summation rolled up through `parent`→epic; cycle time as milestone deltas.
   Exposed via `brana backlog get <id> --field time_spent` / `--field cycle_time`, or a
   dedicated `brana time` rollup — both always with the coverage annotation.
7. **Spec update** (blocked_by 4-6): extend/replace `build-cost-tracking.md` (currently
   `status: research`) into a real feature spec reflecting the final design; update
   `build.md`'s documented LOAD/CLOSE steps.
8. **Docs** (blocked_by 6): user-facing doc for the query command; note the
   shadow-validation requirement before any number is used in a real quote.
