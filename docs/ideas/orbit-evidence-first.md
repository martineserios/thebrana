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

## Evidence run — 2026-06-22 (the experiment, executed)

Ran the pivot the same session. Created 3 genuinely-mechanical `execution:autonomous`
tasks (t-2224 shell completions, t-2225 clap_mangen, t-2226 reference regen) and dispatched
the cleanest (t-2224) through `autonomous-runner.sh --run-one`. **Three findings, all
pointing the same way:**

1. **Corpus is thin.** Of 266 pending S/XS tasks, only ~4 are mechanical code tasks — and
   all are blocked (t-571 → t-570) or carry design choices (CLI chat mode, self-update).
   The research tasks need web + judgment (and the egress sandbox would *block* their web
   access). thebrana's backlog is judgment-heavy by nature. **The runner has no natural queue.**

2. **The shipped V1–V4 sandbox is BROKEN for the real executor.** Sandboxed `--run-one`
   bailed in **25s with "no changes produced."** This is the exact RO-cred-bind →
   "Not logged in" subscription-auth bug found earlier the same day. It shipped "working"
   because the escape battery only ever tested it with a *stub* claude — **no real
   `claude -p` had ever run through the merged sandbox.** The writable-HOME fix exists only
   on the unmerged egress branch.

3. **Even unsandboxed, output wasn't mergeable.** With the sandbox off, `claude -p` actually
   did the work (~2–3 min, real edits) — but the result **failed the runner's `validate.sh`
   gate** and was discarded (worktree removed, dev pristine). Zero usable output in the best
   case. (Open question: was the change wrong, or is the full-`validate.sh` gate mis-calibrated
   as a per-task verifier — e.g. failing on the unrelated stale-binary check?)

**Verdict: yes, this was over-engineered.** We secured a runner that can't authenticate,
added egress to a jail whose auth was already broken, and there's no corpus of tasks it
could do anyway. The 10-minute evidence run surfaced what months of infra-building obscured.

## Next steps (revised by the evidence)

1. **Park orbit** as the default. Don't finish egress, don't build t-2142. Revive only when a
   concrete, recurring, mechanical task stream appears that's painful to do by hand.
2. **If/when revived, the real blockers are (in order):**
   a. Merge the writable-HOME subscription-auth fix (egress branch) — the sandbox is
      non-functional without it.
   b. Recalibrate the verification gate — full `validate.sh` is likely the wrong per-task
      verifier; use the task's own `AC:`/`/goal` grader instead.
   c. Build a real task corpus (or accept the runner doesn't fit a judgment-heavy repo).
3. **Make the escape battery run a real `claude -p` once**, not only the stub — the stub
   hid a total auth failure.
4. Leave `orbit/feat/t-2173-egress-allowlist` unmerged. Egress is moot until a/b/c land.
5. The 3 evidence tasks (t-2224/25/26) stay pending — they're real small improvements
   someone can do by hand anytime; they are not orbit-blocking.
