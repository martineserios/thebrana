---
status: accepted
---
# ADR-083: Unified Project Time & Cost Tracking — Active Effort and Calendar Cycle Time

**Status:** Accepted (2026-08-17)
**Date:** 2026-08-17
**Deciders:** Martín Rios
**Tags:** time-tracking, cost-tracking, harness, backlog, waves
**Tasks:** t-2919 (this ADR) · t-648 (superseded — original build-cost-tracking design, folded in) · t-2920 (idle-cap re-validation, incorporated) · t-2912 (time-tracking epic, parent)
**Supersedes:** [build-cost-tracking.md](../features/build-cost-tracking.md) (t-648's original design — storage-path collision with `ADR-076`'s beat-record path was the trigger; folded in here)
**Relates:** [idea: task-time-tracking](../../ideas/task-time-tracking.md) (full rationale, 3-worker challenger review, and the idle-cap re-validation this ADR incorporates) · [build-receipts feature spec](../features/build-receipts.md) (atomic-write + H2 git-env-scrub precedent this design reuses) · [ADR-076](ADR-076-build-receipts-as-executed-evidence.md) (`git rev-parse --git-common-dir` storage precedent)

---

## Context

There is no reliable way to answer two related but distinct questions about a project:

1. **"How much active Claude effort (time + tokens) went into this?"** — a cost/effort number, needed to answer questions like "was adding the challenger gate worth the added cost?"
2. **"How much real-world calendar time did the whole engagement take — from first quote or design work, through kickoff, to delivery?"** — a cycle-time number, needed to price future proposals accurately.

Neither exists today:

- Task `started`/`completed` fields (task-convention.md) are date-only and populated on only 19% of tasks — nothing auto-writes them, and nothing captures a pre-task "quoting" phase.
- Waves (`{selector, contract, gate, status}`) have no time fields at all.
- `docs/architecture/features/build-cost-tracking.md` (t-648) designed a session-transcript-anchoring mechanism for per-build token cost, but it was never implemented, covers effort only (not calendar cycle time or the pre-task quoting phase), and proposed a storage path (`~/.claude/run-state/{task_id}.jsonl`) that is now occupied by the live LOAD-checkpoint/CLOSE-delete resume mechanism (`build.md` LOAD step / CLOSE step). Reusing it as-is would destroy effort data before it could be aggregated.
- "Project" isn't a first-class type in the backlog — it resolves as the nearest `parent` ancestor with `type:"epic"`.

This ADR folds t-648 into a single design, on a storage path that does not collide with the resume-checkpoint mechanism, and extends scope to cover both metrics.

## Decision

### Two metrics, one rollup

Both metrics roll up through the same project (epic) hierarchy — **never blended into one number**. A project can have 40 hours of active Claude effort spread across a 6-week calendar cycle; both numbers matter together for pricing, and collapsing them would hide the comparison that makes this useful.

**Out of scope for v1, both metrics:** wave-level rollup. Waves pull tasks across epics via selector — "time for wave X" isn't answerable by a parent→epic rollup. A wave-level *view* (sum of a wave's selector-matched tasks' totals) can be added later without changing this design; it is a read, not a new write path.

### Metric 1 — Active effort (Claude time + tokens)

**Scope.** Claude session time only. Non-Claude manual effort (calls, browser review, thinking time) is out of scope, deferred as a separate problem.

**Atomic unit = task, not wave.** Tasks already form a hierarchy (task → parent → epic); summing the hierarchy gives the whole-project total for free.

**Storage.** Markers write to `$(git rev-parse --git-common-dir)/brana/time/<task_id>.jsonl`, atomically (temp-file + rename — the same pattern as `build-receipts.md`'s `mint`). This is a deliberate change from t-648's original `~/.claude/run-state/{task_id}.jsonl` proposal: that path is the live LOAD-checkpoint/CLOSE-delete mechanism (`close.md` deletes it on successful close) and would destroy effort data before aggregation. The two mechanisms coexist as separate files with separate lifecycles for the same `task_id` — resume-checkpoint state (ephemeral) and time-tracking state (durable, aggregated at CLOSE).

**Why this is not a third `~/.claude/run-state/` location.** [ADR-074](ADR-074-step-state-contract.md) settled a specific principle for step-position state: *"we extend it; we do NOT invent a third state location"* (ADR-074 §4) — meaning the checkpoint-resume family (`checkpoint-resume.md`'s original `~/.claude/run-state/{task_id}.jsonl`, joined since by `goal-binding-build-tdd.md`'s `~/.claude/run-state/presence-{session_id}` and `-audit.jsonl` siblings) stays a closed set: user-local, session/build-lifecycle-scoped, cleaned at CLOSE. This ADR does not add a fourth member to that family — `brana/time/` is a different family entirely, distinguished by lifecycle, not just path: it is **durable across the task's entire life** (many builds, many sessions, never deleted, aggregated forward), where every `run-state` sibling is **ephemeral within one build** (written at LOAD, consumed and deleted by CLOSE or a crash-resume). `build-receipts.md`'s `brana/receipts/<task-id>.json` already established the durable, `git-common-dir`-scoped family this ADR's storage joins — `brana/time/` is that family's second member, not a new one.

`--git-common-dir`, never `.git`: one authority shared across linked worktrees, invisible to `git status`, never pushed — this repo runs concurrent sessions in separate worktrees by hard rule, so a per-worktree store would silently disagree with itself (same reasoning as `build-receipts.md`).

**H2 — git-env scrubbing.** Unlike `build-receipts.md`'s `mint`, v1's marker-write step invokes no `argv` subprocess of its own — the exposure here is narrower: the marker-writing step's **own** `git rev-parse --git-common-dir` call (used to resolve the storage path) must not inherit a leaked `GIT_DIR`/`GIT_WORK_TREE`/`GIT_INDEX_FILE`/`GIT_OBJECT_DIRECTORY`/`GIT_COMMON_DIR` from its caller — a leaked value would relocate the marker write into a foreign repository, or worse, resolve `brana/time/` into the wrong `git-common-dir` entirely (`pattern_git-hook-env-leaks-into-executed-tests`; live incident precedent in `build-receipts.md` H2). The 5-var denylist is the same one `build-receipts.md`, `system/hooks/red-verification.sh`, and both `check-oracle`/`ship-brana-oracle` test scripts already unset independently. This scrubbing requirement must be named as its own explicit test case alongside the atomic-write stress test (see Next Steps #3 in the idea doc) — a silent gap in v1 test coverage, not a design gap.

**Bracket model.** A task's total time is the sum of **all `(start_ts, end_ts)` sub-spans ever recorded for that `task_id`**, potentially across many transcript files/sessions — not a single START/CLOSE pair. This makes cross-session resumption (crash, `/compact`, days-later resume) fall out cleanly: an old session's bracket end is its last real turn's timestamp (orphaned-bracket fallback), and resuming a task in a new session opens a fresh bracket for the same `task_id`. No special resumption logic needed beyond "sum all brackets for this `task_id`."

**One open bracket per session, serialized.** LOAD refuses to open a new task's bracket while one is already open in the same session — the current task must CLOSE first. This matches how top-level work actually happens: parallelism comes from spawning subagents under one active task, not from flipping which task is "active" mid-session.

**Subagent/fork fan-out excluded from v1's sum.** A fork's real work collapses to a single `tool_use`→`tool_result` turn pair in the parent transcript; the gap between those two timestamps would otherwise be swallowed by the idle cap exactly like real idle time, silently under-reporting exactly the tasks built with heavy delegation. Any task where delegation was used gets a `coverage: partial` flag rather than a silently-wrong number. (Whether fork subagents share the parent's transcript file or write their own is unverified — an implementation-time check, not resolved here; the exclusion holds either way for v1.)

**Coverage boundary.** Only tasks executed via `/brana:build` are measured — `kind: research/design/docs` tasks that never invoke `build.md` structurally show zero. This is a named v1 boundary, not a bug; extensible later by adding the same marker pattern to other skills (`/brana:research`, `/brana:fix`) if needed.

**M+-gate decoupling.** Marker-writing applies to every task through `/brana:build`, regardless of effort size — decoupled from the existing, unrelated `~/.claude/run-state/{task_id}.jsonl` resume-checkpoint mechanism, which is gated to M+ builds only for a different reason (checkpoint overhead isn't worth it for trivial tasks that finish before ever needing to resume). Time-tracking markers are cheap appends and don't inherit that gate — S-effort tasks get coverage too.

**Measurement method: turn-delta summation with a 15-minute idle cap, not bracket-endpoint spans — re-validated, incorporating t-2920.**

Originally validated on n=1 (a fast text-only brainstorm session: 63.5h naive span vs. 0.51h turn-delta-summed, 124x difference; 239/262 sub-cap gaps under 5s, max legit gap ~5min). **Re-validated 2026-08-17 (t-2920)** against 5 additional real session transcripts spanning build, bug-fix, and research task kinds (2,198–7,652 turns each, 1.35h–27.25h naive span):

| Session | Turns | Naive span | Capped active | Gaps >15min | Max sub-cap gap |
|---|---|---|---|---|---|
| cc81cf5d | 7,652 | 27.25h | 6.51h | 9 | 12.92min |
| deb2eb19 | 4,905 | 23.40h | 3.83h | 2 | 8.09min |
| f021c8b3 (bug/research) | 2,893 | 15.33h | 2.84h | 2 | 11.53min |
| e644471f | 4,372 | 2.65h | 2.59h | 1 | 12.29min |
| dccbeb3d | 2,198 | 1.35h | 1.29h | 1 | 8.81min |

Every over-cap gap found across all 5 sessions was either an overnight/multi-hour idle break, or an `AskUserQuestion` tool call awaiting user input (4.2–84.1 minutes observed) — genuine non-active time the cap is correctly designed to exclude. Zero cases of a blocking `Bash`/`Agent`/`Task` tool call (test suite, build, subagent spawn) exceeding ~5 minutes were found in any sampled session — the risk originally named in the n=1 caveat did not materialize. **The 15-minute idle cap is confirmed and locked in** by this ADR — no change to the constant.

Residual, non-blocking risk: the closest sub-cap gap observed was 12.92 minutes (~2 minutes below threshold), so a legitimately-engaged-but-slow turn could plausibly cross 15 minutes in a larger/slower session than any sampled. Worth a passive watch post-launch, not a blocker. Implementers and future readers should also note: `AskUserQuestion` waits are an *expected* source of long (sometimes 60–90+ minute) gaps that the cap will correctly exclude — a large gap attributed to `AskUserQuestion` is not a tracking bug.

**Aggregation timing: synchronous at CLOSE**, inheriting t-648's pattern — the computed number is stored, not a pointer into the transcript, so transcript retention/rotation is never a dependency for historical totals.

**Output requirement — no bare numbers.** Every query surface (`brana backlog get --field time_spent`, a `brana time` rollup) must emit a coverage annotation alongside the figure — e.g. "40.2h across 6/7 tracked tasks, 1 flagged partial (delegation used), idle-cap applied to 14 gaps" — never a bare `time_spent: 40.2h`. A shadow-validation period (compute silently for several weeks, compare against manual estimates) is required before this number is wired into any real client quote or invoice.

### Metric 2 — Real-world elapsed time (quote → kickoff → delivery)

Applies to all projects uniformly, not just client/venture engagements — internal/infra epics simply leave the milestone fields empty.

**Source = explicit milestone fields, with derived signals as fallback.** Three timestamps on the epic/project task: `quote_started`, `kickoff_date`, `delivered_date`.
- `kickoff_date` fallback → timestamp of the epic's first child task moving to `in_progress` (or first branch cut under the epic's slug).
- `delivered_date` fallback → timestamp of the last child task's completion, or a ship/merge-to-main event tagged with the epic.
- `quote_started` fallback → the epic task's own creation timestamp, as a weak, explicitly-approximate proxy — always surfaced with an "approximate — quoting likely started earlier" annotation, never presented as precise. A true manual `quote_started` always overrides the proxy.

These fields are additive and independent of the legacy `started`/`completed` fields — no backfill, no authority conflict, since they measure different things (a coarse date-only lifecycle marker vs. precise milestone timestamps). This is deliberately not the same clock as Metric 1.

## Consequences

- Folding t-648 into this design means cost and duration share one marker mechanism instead of two competing efforts; any future addition to what's measured only needs to be added once.
- Marker-writing lives inside `build.md`'s LOAD/CLOSE steps, decoupled from the M+ gate → every code task gets brackets automatically, all effort sizes. Risk (confirmed via challenger review): concurrent worktree sessions writing to shared marker state need atomic writes — not optional, given this repo's hard rule on concurrent worktrees. Addressed by the atomic temp-file+rename requirement above.
- Metric 2's derived fallbacks (kickoff/delivery) reuse existing task lifecycle events — no new instrumentation needed for those two fields. `quote_started` stands out as the one field with no strong safety net; a lightweight reminder mechanism (e.g. a prompt at `/brana:brainstorm` or `/brana:backlog add` time when a new client engagement is detected) is a good follow-up, not core scope.
- **Combined CLOSE-latency budget with `build-receipts.md`'s `mint`.** `mint` is designed to run at CLOSE step 1 and will be measured against its own kill-threshold K2 once implemented and live for 20 gated merges (`build-receipts.md`: median wall-clock `mint` adds to CLOSE > 60s → make `mint` opt-in; neither `mint` nor K2's first reading exist yet as of this ADR). This ADR adds a second CLOSE-side write (bracket-close + aggregation) at the same integration point. When both are live, K2's accounting will be `mint`-only — it will not see latency this design adds. Track the two together as one combined CLOSE-latency budget once both ship, not two independently-passing measurements that can jointly regress CLOSE wall-clock unnoticed; if the combined figure trends toward K2's 60s line, that is a signal even if `mint` alone stays under it.
- **Prompt-cache sharing across forks — token-cost double-counting risk, not blocking.** Metric 1 already excludes subagent/fork time from the duration sum (the fan-out exclusion above). The parallel risk on the token-cost side of Metric 1 (not yet built — cost aggregation will share this same bracket mechanism) is that prompt-cache reads shared between a parent session and its forked subagents could be attributed to both, double-counting cache-read tokens across the two. Since forks are already excluded from v1's duration sum for the reason above, this does not block v1, but the future cost-aggregation implementation must not assume token counts are cleanly additive across parent/fork boundaries without checking this.
- Coverage rot risk (deferred, non-core): if marker-writing is later dropped from `build.md` without anyone noticing, Metric 1 silently degrades. A periodic coverage-percentage check (same shape as the existing stale-task check) is the mitigation, filed as follow-up.
- `build-cost-tracking.md` (t-648) is superseded by this ADR — its storage path (`~/.claude/run-state/{task_id}.jsonl`) and single-span anchoring model are replaced by `brana/time/` and the many-sub-spans bracket model. Its core insight (per-turn `message.usage` in the session transcript is the data source) is retained.

## Non-Actions

- **Wave-level rollup** is explicitly out of scope for v1 (both metrics) — see "Two metrics, one rollup" above.
- **No number from this design is wired into a real client quote or invoice** until the shadow-validation period (Metric 1) completes.
- **No backfill** of the legacy `started`/`completed` fields, and no authority conflict introduced with them.
- **No change to the 15-minute idle-cap constant** — re-validated and locked, not renegotiated.

## References

- [docs/ideas/task-time-tracking.md](../../ideas/task-time-tracking.md) — full research, 3-worker adversarial challenger review (18 findings, all resolved), and the idle-cap re-validation block this ADR incorporates verbatim.
- [docs/architecture/features/build-cost-tracking.md](../features/build-cost-tracking.md) — superseded by this ADR (t-648).
- [docs/architecture/features/build-receipts.md](../features/build-receipts.md) — atomic-write and H2 git-env-scrub pattern precedent reused here.
- [ADR-076](ADR-076-build-receipts-as-executed-evidence.md) — `git rev-parse --git-common-dir` storage precedent.
- [ADR-074](ADR-074-step-state-contract.md) — the `~/.claude/run-state/` closed-family principle this ADR's storage decision explicitly does not violate (see "Why this is not a third run-state location" above).
- [docs/architecture/features/checkpoint-resume.md](../features/checkpoint-resume.md) and [docs/guide/features/checkpoint-resume.md](../../guide/features/checkpoint-resume.md) — origin of the `~/.claude/run-state/{task_id}.jsonl` checkpoint family this ADR's storage is deliberately distinct from.
- [docs/architecture/features/goal-binding-build-tdd.md](../features/goal-binding-build-tdd.md) — the `run-state/presence-{session_id}` and `-audit.jsonl` siblings, same family as checkpoint-resume.md.
