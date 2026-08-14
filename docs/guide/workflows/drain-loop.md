---
title: Wave drain loop — the committed runner procedure
status: active
created: 2026-08-13
task: t-2813
adr: ADR-079
produced_by: [docs/architecture/decisions/ADR-079-backlog-drain-loop-handoff.md]
---
# Wave Drain Loop

> First entry of the loops library ([loops-library.md](../../ideas/drained/loops-library.md) — the
> catalog this proves the pattern for); the approach behind both is
> [loop-first-redesign.md](../../ideas/drained/loop-first-redesign.md).

The runner procedure for draining a wave with `/loop` (ADR-079 §2/§2b/§3). This
file IS the committed prompt — a loop is *trigger + committed prompt + a
termination check the agent can't game*, and this is the middle piece. The
durable state (tasks.json: wave status, task status, `ac_state`) is the loop's
memory; each beat re-reads it and trusts nothing from prior beats.

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
6. Open the queue: `brana backlog wave drain wave-N`

## The loop prompt (supervised)

```
/loop Wave-N drain pump (supervised, ADR-079 §2b). Each beat:
(1) PREFLIGHT (cheap, no-op fast): `brana backlog wave pull wave-N`.
    - pulled:null + at_limit    → report "at limit (live/limit)", back off 20+ min.
    - pulled:null + none_eligible → report the counts (matched/unapproved/parked);
      if matched is 0 the wave may be done — tell the human, back off 30+ min.
    - error "not draining"      → the wave was requeued/shipped — STOP the loop.
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

| Verb | Why |
|---|---|
| `brana backlog ac <id> approve` / MCP `backlog_ac_approve` | Approval is the human trust boundary between selector-match and autonomous execution. A gate armed by the party it constrains is no gate (ADR-079 §1; ADR-076 D4). The loop may run `ac-propose`; only a human approves. |
| `brana backlog wave set <id> status shipped` | No auto-ship (wave-gate-enforcement §1.4). Empty pull ≠ done. |
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
