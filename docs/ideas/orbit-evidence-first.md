---
title: Orbit — Evidence Before Infrastructure (start smaller)
status: idea
created: 2026-06-22
relates:
  - docs/ideas/runner-capability-isolation.md
  - docs/architecture/features/autonomous-runner.md
  - docs/architecture/features/learned-eligibility.md
  - docs/architecture/substrate-end-state.md
---

# Orbit — Evidence Before Infrastructure

> Brainstormed 2026-06-22, after a full session spent on the t-2173 egress sandbox.
> Trigger: "maybe we are overengineering the thing and we should start smaller."

## Problem

The **orbit** epic (autonomous runner) is **infrastructure ahead of demand**. The
diagnosis, stated plainly:

- **Zero** tasks have ever been merged through the runner (`--run-one`).
- **Zero** pending tasks are tagged `execution:autonomous`. The only autonomous-tagged
  task in the backlog is t-2142 — itself a *design* task about learned eligibility, not
  work the runner can pick up. **The runner has no queue.**
- An entire session (2026-06-22) was spent hardening the executor's network egress
  (t-2173 V5/V6) — securing the "external communication" leg of a threat model that only
  activates when the runner runs real, attacker-influenceable tasks. It doesn't.

This is the classic over-engineering pattern: **harden the infrastructure before proving
the infrastructure is worth having.** Pre-mortem (user picked "all of the above"):
1. The runner never runs real tasks — we keep building infra instead.
2. Task quality is too low — supervising it costs more than doing the work manually.
3. Claude Code ships native autonomous/sandbox features that make the custom runner moot.

These aren't three risks; they're one: **orbit bets on a future that may not arrive, while
consuming sessions that could ship things users can touch.**

## The reframe — the missing piece is the corpus, not the cage

"Start smaller" does **not** mean a smaller sandbox. It means a different bottleneck. The
runner can only create value if there are tasks **written in a format it can complete
unattended** — concrete, scoped, no judgment calls, with real `AC:` lines. That's a
*habit/corpus* gap, not a *tooling* gap. No amount of bwrap/egress work produces a single
mergeable task.

The security work already merged (V1–V4: secrets absent from the jail, env cleared, no
writes outside the worktree, rlimits) is **genuinely solid and worth keeping** — but its
value is latent until the runner actually runs tasks.

## Proposed direction — pivot to evidence (chosen path)

Prove or disprove orbit with the tools that already exist, in one session, no new infra:

1. **Write 5–10 runner-ready tasks** in the backlog — `execution:autonomous`, S/XS, concrete,
   with explicit `AC:` lines. Candidates: "add validate check for X", "regenerate
   spec-graph after these edits", "update errata count in roadmap", small doc/lint fixes.
2. **Run 3 of them** through `brana orbit run --one` with the **already-merged V1–V4
   sandbox**. Human reviews every diff (status quo — no unattended batch).
3. **Measure the output quality.** Mergeable as-is? ~5 min review or ~30? Heavy edits?

The result decides orbit's fate on **evidence**, not architecture:
- Mostly-mergeable with light review → orbit has legs; *then* finish the egress work.
- Needs clarification mid-run → task format is the real problem; fix that first.
- Needs heavy editing → the value proposition is weak; park orbit.

## What this means for the in-flight egress work

The egress branch `orbit/feat/t-2173-egress-allowlist` (proven in isolation, committed,
unmerged) **stays exactly where it is.** It isn't wrong — it's *premature to finish* before
we know the runner is worth having. Egress only matters once the runner runs untrusted,
unattended tasks (`--run-batch`), which is gated behind evidence we don't yet have.

V1–V4 + the documented egress gap is a defensible "good enough" resting point for t-2173.

## Risks

- **Top risk (pre-mortem):** the infrastructure-treadmill — secure it → test it → edge case
  → more infra, never running a real task. **Mitigation:** the evidence pivot *is* the
  brake — it forces a real `--run-one` before any more sandbox investment.
- **Second risk:** writing "runner-ready" tasks just to feed the runner is itself make-work
  if those tasks weren't going to be done anyway. **Mitigation:** only draw from tasks that
  already exist or are genuinely needed; if you can't find 5 real ones, that *is* the
  answer (orbit has no demand → park it).

## Second-order effects

- **Write runner-ready tasks → 1st: the runner gets a queue → 2nd (surprise):** the
  discipline of writing concrete, AC-bearing, judgment-free tasks improves the *whole*
  backlog's quality and testability — value that accrues even if orbit is later parked.
- **Run 3 tasks unattended-ish → 1st: get quality data → 2nd (surprise):** the failure
  modes you observe are the *real* spec for what the runner needs next — which may be
  nothing like egress (e.g., better task templating, or an AC-as-goal grader), redirecting
  the whole epic away from the security rabbit hole.

## Next steps

1. Draft 5–10 `execution:autonomous` S/XS tasks with `AC:` lines (no new code).
2. `brana orbit run --one` on 3 of them; capture review-effort + mergeability per task.
3. Decide from evidence: finish egress / fix task-format / park orbit.
4. Leave `orbit/feat/t-2173-egress-allowlist` unmerged until step 3 says "finish egress".
5. Consider marking t-2173 "good enough" (V1–V4 + documented egress gap) regardless.
