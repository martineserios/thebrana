---
title: Wave drain loop — the committed runner procedure
status: active
created: 2026-08-13
task: t-2813
adr: ADR-079
produced_by: [docs/architecture/decisions/ADR-079-backlog-drain-loop-handoff.md]
---
# Wave Drain Loop

> **Superseded for epics** by [epic-drain.md](epic-drain.md) (ADR-080) — that loop generalizes this one from "one wave, hand-armed" to "walk an epic's wave graph, arm each wave as its gate clears." This file stays live and is still the single source for what happens *inside* one wave once it's armed (full build framework, human merge valve, denied verbs) — epic-drain inherits that, it doesn't reimplement it. Use this file directly only for a single hand-armed wave outside any epic-drain walk.
>
> First entry of the loops library. Catalog entry: [system/loops/drain-loop.md](../../../system/loops/drain-loop.md)
> (frontmatter + pointer back here — this file stays the single source for the procedure).
> Contract: [loops-library.md](../../architecture/features/loops-library.md). Shape/approach:
> [loops-library.md (idea)](../../ideas/drained/loops-library.md), [loop-first-redesign.md](../../ideas/drained/loop-first-redesign.md).

The runner procedure for draining a wave with `/loop` (ADR-079 §2/§2b/§3). This
file IS the committed prompt — a loop is *trigger + committed prompt + a
termination check the agent can't game*, and this is the middle piece. The
durable state (tasks.json: wave status, task status, `ac_state`) is the loop's
memory; each beat re-reads it and trusts nothing from prior beats.

## Sizing rules (ADR-086 §1, t-3165)

Two cut rules govern what enters this loop — apply them at plan/decompose
time, not after a pull goes wrong:

- **A task is one fresh context window.** If an agent can't carry the task
  from pull to report inside a single context, it's cut wrong — decompose it
  (Pocock's "task = one fresh context window" rule, adopted in ADR-086 §1).
  Under-decomposition shows up later as judge-panel escalations; the fix is
  the cut, not a bigger panel.
- **A wave is one AFK cycle.** A wave's selector should match what a human
  expects to review and ship after one away-from-keyboard stretch — the
  human ship valve is the throttle, so a wave sized past one sitting just
  queues at the valve.

## The standing wave (ADR-086 §5, t-3161)

One wave, `wave-standing` (selector `role:ready-for-agent`, no contract, no
gate, provisional `wip_limit` 2 — revise from real drain records), is **always
draining**: Pocock's AFK loop expressed as a wave. Singletons never need a
bespoke wave — an `ac approve` alone puts a task on the standing frontier.
Its pull differs from a bespoke (tag:/parent:) wave in three ways, all
implemented in `wave_pull_decision` (`brana-core/src/tasks/wave.rs`):

- **Ordering:** candidates sort by `priority` (P0 first, absent last) then
  `created` ascending before the first eligible is taken. Bespoke waves keep
  tasks.json array order — hand-picked sets stay the operator's sequencing.
- **Bespoke precedence:** a task matched by another *draining* tag:/parent:
  wave is pulled by that wave first — the standing pull defers it (visible as
  the `deferred` count in a `none_eligible` report). A merely `queued` bespoke
  wave does not shadow the standing pool.
- **WIP live count:** roles are status-derived (an `in_progress` task derives
  `claimed`), so the standing wave counts as live the `in_progress` tasks that
  *would* derive its role were they pending, minus bespoke-owned ones. Manual
  `backlog start` on an approved task therefore counts against the standing
  `wip_limit`, same as the tag-wave precedent.

Everything else is identical: same pump (`wave pull`), same denied verbs, same
human valves. Reading a standing `none_eligible` report: `unapproved`/`parked`/
`human` are structurally always 0 (role membership already implies approved ∧
¬parked ∧ ¬human) — only `blocked` and `deferred` carry signal. Latency note (ADR-086 F12): the standing frontier is small while
`ac approve` adoption grows — the human approve valve is the throttle, and
that is the design, not a stall.

## Prerequisites (the pipeline, front to back)

```
tasks tagged wave:<name> ──▶ ac-propose ──▶ YOU: brana backlog ac <id> approve ──▶ wave drain ──▶ the loop pulls
        (queue)                (proposer)         (the human valve)                  (opens queue)     (this file)
```

1. Tag the tasks: `brana backlog set t-N tags +wave:<name>` — or skip tagging
   entirely with a `parent:<id>` selector (ADR-080 §1): the wave then matches
   every descendant of a milestone/phase node via the parent chain.
2. Create the wave: `brana backlog wave add --name <name> --selector tag:wave:<name> --contract "..."`
   (or `--selector parent:<ms-id>` for plan-structure waves)
3. Optionally bound it: `brana backlog wave set wave-N wip_limit 1`
4. Approve each task's AC (**human-only** — see Denied verbs): `brana backlog ac t-N approve`
5. **Rehearse (optional, law 6):** `brana backlog wave pull wave-N --dry-run` —
   reports the would-pull decision and writes nothing. Works on a still-queued
   wave by simulating as-if-draining (labeled `simulated_draining` in the
   output), so a graph can be checked before arming.
   Add `-n <N>` to rehearse a full N-wide beat (ADR-090 §1): the output lists
   every task the beat would claim under `would_pull`, plus the `at_limit` /
   `none_eligible` tail that stopped it short of N. Rehearsal only — `-n`
   above 1 without `--dry-run` is refused, not quietly narrowed to one pull.
6. Open the queue: `brana backlog wave drain wave-N`

7. **Arm the verb guard:** launch the runner session with `BRANA_RUNNER=1` in
   its environment (`BRANA_RUNNER=1 claude`). This arms the
   `runner-verb-guard.sh` PreToolUse hook (t-2827), which mechanically denies
   the Denied-verbs table below — the agent cannot modify the harness env, so
   it cannot disarm it. An unflagged session falls back to this doc being
   advisory only.

## The loop prompt (supervised)

```
/loop Wave-N drain pump (supervised, ADR-079 §2b). Each beat:
(1) PREFLIGHT (cheap, no-op fast): `brana backlog wave pull wave-N`.
    - pulled:null + at_limit    → report "at limit (live/limit)", back off 20+ min.
    - pulled:null + none_eligible → report the counts (matched/unapproved/parked/blocked/deferred);
      eligibility is pending ∧ approved ∧ ¬parked ∧ every blocked_by `completed`
      (a cancelled blocker does NOT resolve — remove it from blocked_by; ADR-079 §2 amendment;
      deferred = left to a draining bespoke wave, standing-wave pulls only — ADR-086 §5).
      If matched is 0 the wave may be done — tell the human, back off 30+ min.
    - error "not draining"      → the wave was requeued/shipped — STOP the loop.
    - error "can never drain"   → the wave's role: selector isn't ready-for-agent
      (t-3250 valve guard, legacy data) — STOP and tell the human to fix the wave's
      selector; re-pulling cannot succeed.
(2) If a task id was pulled: work it through the FULL build framework —
    /brana:backlog start <id> (worktree cut from dev, TDD, gates, challenger).
(3) At build CLOSE: present the merge command and WAIT — never merge to dev
    inside a beat; the human is the merge valve.
(4) Never set status:completed yourself outside the build framework's CLOSE,
    never set wave status:shipped ("no eligible tasks" ≠ "the wave is done").
(5) Pace: short delays while actively building; 20-30 min when waiting on the
    human valve or an empty queue.
```

`wave pull` is atomic (one lock: fresh read → eligibility → write `in_progress`)
— two concurrent beats cannot double-pull, and a human starting a wave-matched
task manually counts against `wip_limit` on the next pull. Since t-2841
(ADR-080 §5) the pull also takes a **lease** `{claimant, expires}` in the same
critical section (claimant via `--claimant`, default `wave-pull:{session|pid}`;
TTL 24h). Any status write acks/clears it; manual `backlog start` takes no
lease. Expired leases are surfaced by the future watchdog and reset by the
`lease-reclaimer` pump (loop-first epic) — never by this loop.

## Denied verbs — the runner must never run these

Mechanically enforced in `BRANA_RUNNER=1` sessions by `runner-verb-guard.sh`
(t-2827) — except `status completed` outside build CLOSE, which a hook cannot
distinguish from the framework's own CLOSE and stays procedural.

| Verb | Why |
|---|---|
| `brana backlog ac <id> approve` / MCP `backlog_ac_approve` | Approval is the human trust boundary between selector-match and autonomous execution. A gate armed by the party it constrains is no gate (ADR-079 §1; ADR-076 D4). The loop may run `ac-propose`; only a human approves. |
| `brana backlog wave approve <wave-id>` / MCP `backlog_wave_approve` (with `confirm_ids`) | Same trust boundary as `ac approve`, batched (ADR-080 §4, t-2842) — a coarser valve is still the human's valve, not the runner's. The runner may surface that a wave has `ac_state:proposed` tasks (visible in a preview call); it must never supply `confirm_ids` itself. |
| `brana backlog wave set <id> status shipped` / `brana backlog wave ship <id>` (t-3022 alias) | No auto-ship (wave-gate-enforcement §1.4). Empty pull ≠ done. The alias is the same valve — denied identically. |
| `git merge` into `dev`/`main`, any push to production | ADR-060: executors return branches; a human integrates and ships. |
| `brana backlog set <id> status completed` (outside build CLOSE) | Completion is graded (acceptance criteria, gates), not asserted. |

## Unattended mode — NOT enabled

This procedure is **supervised-only**: a human is present, watching beats, and
operating the merge valve. Unattended operation (overnight ScheduleWakeup /
detached runner) is hard-gated on the **ADR-062 executor sandbox** — task
subject/description/AC content is untrusted input flowing into executor
prompts, and until the sandbox gate is satisfiable the loop must not run
without a human present. Do not remove this section without amending ADR-079.

## Mechanics reminders (shipped `/loop` semantics)

Session-scoped; hard 7-day expiry; no catch-up for missed fires; Esc stops a
waiting loop. Run drain loops in a dedicated lean session, not your fat
interactive one — cost per beat ≈ context size. Cheap preflight first, always.
