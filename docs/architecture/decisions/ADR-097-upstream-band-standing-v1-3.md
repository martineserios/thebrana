---
status: proposed
extends: docs/architecture/decisions/ADR-084-upstream-skill-band-vendored-pocock-skills.md
respects: docs/architecture/decisions/ADR-061-goal-integration-three-primitive.md
informs: docs/architecture/decisions/ADR-085-skills-as-stations-no-atom-schema.md
---

# ADR-097: The upstream skill band is standing — pin v1.3.1, admit `tdd` and `pr`, hold `retro`

**Status:** Proposed (2026-10-07) — awaits operator acceptance and one context-isolated challenger pass; nothing under `system/` moves before that.
**Date:** 2026-10-07
**Deciders:** Martín Rios
**Tags:** skills, upstream-band, mattpocock-mining, adr-084, adr-061, tdd, merge-valve
**Tasks:** t-3263 (evidence) · t-2981 (organ 4, approved) · penciled P1–P6 in [ideas/pocock-v13-adoption.md](../../ideas/pocock-v13-adoption.md)
**Extends:** [ADR-084](ADR-084-upstream-skill-band-vendored-pocock-skills.md) — §7a: "that remains a separate follow-up ADR/amendment." This is it.
**Respects:** [ADR-061](ADR-061-goal-integration-three-primitive.md) — the `/goal` span and grader immutability survive the `tdd` organ unchanged.
**Informs:** [ADR-085](ADR-085-skills-as-stations-no-atom-schema.md) D4/D6 — `tdd` is the one extraction build's granularity floor admits; the station contract is read off its adapter.
**Evidence:** [research/2026-10-07-pocock-recheck.md](../../research/2026-10-07-pocock-recheck.md) (skills v1.3, ring-fit, F1–F6) · [research/2026-08-22-pocock-alignment-decision-matrix.md](../../research/2026-08-22-pocock-alignment-decision-matrix.md) §0 · ADR-084 §7a pilot outcome

---

## Context

ADR-084 (2026-08-17) admitted a new band — upstream skills vendored verbatim, pinned, wrapped
by thin brana adapters — as **pilot-only**. The pilot (`diagnosing-bugs` → `diagnose-hard-bug`,
t-2834) was evaluated 2026-08-30 and read **EXPAND** on all three pre-registered proxies.
Two more organs followed (`code-review` → `two-axis-review`, t-2835; `wizard` →
`provisioning-wizard`, t-2836). The band now has three organs, all pinned `v1.2.3`, and §7a
explicitly deferred the question of whether it is a *standing* band.

On 2026-10-04 upstream shipped v1.3.0/v1.3.1. The quarterly recheck (t-3263) found:

- Two of the three vendored organs changed upstream: `diagnosing-bugs` (PR #1209: prove a
  forced red landed before trusting it; reads `GLOSSARY.md`) and `code-review` (standards-file
  search, foreground sub-agents, tracker doc). First measured drift on the band.
- Three graduated skills: `implement-spec`, `pr`, `retro`. Placed on brana's rings they are
  Beat, Beat-at-the-merge-valve, and Knowledge respectively. None has an Epic-ring
  counterpart; none removes a brana valve.
- `CONTEXT.md` became `GLOSSARY.md` across eleven skills. ADR-084 §3's remap sentence names
  the old file.
- `SCOPE.md` + `.out-of-scope/` (2026-10-06): no new-skill contributions upstream, ever;
  only GitHub/GitLab/local-markdown backends, with "Other" as a prose file the user owns.
  Vendoring is therefore the *only* relationship brana can have with this repo, and brana's
  prose adapter (`docs/agents/issue-tracker.md`) is the sanctioned path, not a workaround.

The operator's direction (2026-10-07): adopt his implementation discipline; go idea → ADR →
spec first, implementation later.

## Decision

### D1 — The band is standing

The pilot's EXPAND stands as the admission. From this ADR on, the band has:

- **One pin for the whole band.** Every organ carries the same `pinnedRef`. A bump moves all
  organs together (D2) so the gauge reports one number, not three.
- **A manual pump.** The bump procedure is a documented, hand-run sequence
  ([features/upstream-band-pin-bump.md](../features/upstream-band-pin-bump.md)). ADR-084 §1's
  instruments (`reconcile --scope pocock-sync`, a standing gauge) stay **unbuilt** until the
  third bump — two data points are not a trend (ADR-084 "Negative (accepted)").
- **Kill criteria = ADR-084 §7's proxies, per organ, read at every bump:** `adapter_churn`
  ≥ 2 commits on an adapter between bumps, zero organic invocations across a bump window, or
  a bump that needs adapter rework on first touch. One organ failing kills *that organ*
  (revert to port-and-own), not the band. Two organs failing in the same window re-opens
  this ADR.

### D2 — Pin moves to v1.3.1 for the three existing organs

`diagnosing-bugs`, `code-review`, `wizard`: `pinnedRef: v1.2.3` → `v1.3.1`. Each adapter's
`redirect-check.md` is re-verified against the new `SKILL.md` (ADR-084 §1 pump obligation);
`computedHash`/`files[]` regenerated with `system/scripts/skills-lock-hash.sh`, never by hand
(ADR-084 §7a). The #1209 step in `diagnosing-bugs` maps onto brana's `red-verification.sh`
registration — the adapter notes the correspondence, it does not re-implement it.

### D3 — Admit `tdd` (organ 4) and `pr` (organ 5)

- **`tdd`** — as t-2981 already approved, with one addition from the recheck: the adapter
  cuts his loop **at green**. Red→green runs inside the `/goal` span (ADR-061 §4 inv. 3);
  refactor runs in brana's existing post-green step outside the predicate; new tests register
  red through `red-verification.sh` into `tests_required[]` (inv. 2). His skill has no
  termination engine or grader-immutability rule — the adapter is where both are
  re-asserted, or ADR-061 Stage 2 silently breaks. Spec:
  [features/tdd-organ-build-loop.md](../features/tdd-organ-build-loop.md).
- **`pr`** — new. Model-invoked upstream; brana keeps it model-invoked so it fires on
  feature-branch PRs, not only the dev→main ship. Three headings are mandatory (Summary as the
  smallest visual · Evidence before/after · Merge Danger: door + blast radius).
  `/brana:ship` replaces its `git log --oneline` body with the organ's output; `pr-reviewer`
  reads the Merge Danger section as input and challenges it. Spec:
  [features/pr-body-organ.md](../features/pr-body-organ.md).

**Merge Danger as a predicate.** The `pr` organ's door + blast-radius call is the first
machine-readable reversibility statement brana will have per PR. It is recorded here as the
intended input for loop-first's "L2 trivially-safe Merger" rung (t-2820): a rung that merges
on its own may do so only for `two-way` doors with a small radius, and the morning review's
revert-and-tighten cycle (pstack, research §6c) is the matching failure path. Not built here;
named so the organ is shaped with that consumer in mind.

### D4 — Two `implement-spec` invariants enter the Beat contract; the skill does not

brana's runner *is* his "deterministic loop," which he ranks above `implement-spec`
("worse than doing a deterministic loop, but a good way to get started"). The skill is
KEEP-BRANA. Two of its invariants are adopted as prose in the Beat contract:

1. **Explore once, point after.** Exploration output is written once, outside the repo,
   and every later implementer receives a pointer, never a copy. (Already brana's
   pointer-not-paste rule, ADR-086 §7 — now stated for the runner's exploration step too.)
2. **Sync the integration tip before reporting done.** Before `/brana:close` presents the
   merge command, and before a runner instance reports a task complete, the branch merges
   the current `dev` tip so the human merge is fast-forward or trivially clean. The human
   stays the merge valve; the valve just stops receiving conflicted branches.

Home for both: `system/skills/close/phases/` (merge-command step) and
`docs/guide/workflows/epic-drain.md` §Merge. Penciled as P4.

### D5 — `retro` is held, not rejected

The seven-category environment lens is a genuine gap: nothing in brana reads session logs or
treats the environment (hooks, rules, CLAUDE.md weight, tool cost) as the subject of a
retrospective. It is *not* vendored this round because its home is undecided — a step in
`/brana:close` EXTRACT, a quarterly run like `verify-docs`, or neither — and because its
author's operating rule must travel with it: human-in-the-loop, sampled sessions, never a loop
("automating this means the agent will get itself into a loop where it continually finds
false positives"). brana's self-improvement machinery leans toward automation; the decision
task (P5) must say where the human sits before the organ lands.

### D6 — `chief-of-staff` and `loop-me` are watched

Both are `in-progress/` upstream. Both re-derive in one session what brana persists in epic
nodes, waves and memory. Re-evaluate at the next quarterly recheck (t-3477) if either
graduates. Two of `loop-me`'s terms are worth citing now without adopting anything:
**push right** (defer the checkpoint as far as it will go) and **brief** (the checkpoint
presents a decision-ready summary, never the raw output) — brana's valve and digest.

### D7 — GLOSSARY remap supersedes ADR-084 §3's CONTEXT.md sentence

Wherever an upstream skill reads `GLOSSARY.md` / `GLOSSARY-MAP.md`, the adapter maps to
`docs/domain/` — today `MODEL-001-brana-core.md`; `docs/domain/glossary.md` does not exist
and is not created by this ADR (t-3013 owns the glossary-building discipline). Adapters keep
the "2–3 most relevant `docs/architecture/*.md` + the task's own context" fallback ADR-084 §3
already prescribes.

### D8 — Same-day sweep additions enter the plan, not the band

The deeper sweep (research §6) found four adoptables that are practices, not skills to vendor.
They join the penciled plan as P7–P10 (idea doc) and are decided here only to the extent of
*where they land*:

1. **Rules → hooks audit** (S1): each always-load rule line is tested with "could a hook exit 2
   with this message?"; those that can become hooks and the line is deleted. The run-once pass
   is a task (P7, filed on acceptance), not a sentence here, so the backlog and Check 68 can
   see it; the recurring form is a `/brana:reconcile --scope rules-to-hooks` pass on the
   `retro` cadence (D5). **Gauge the cadence reads:** authored-rules bytes and headroom as
   printed by `system/scripts/context-budget.sh` (the number `tests/procedures/
   test-context-budget-split.sh` AC4 asserts on the live tree), plus the rule line count; the
   scope is working if headroom rises between runs without a hand trim. This is the class fix
   behind t-3470's symptom trim (two rule files shortened by hand on 2026-10-06 to keep that
   test green) and the operational form of `retro`'s mechanical→check rule.
2. **Triage repro gate** (S2): `ac-propose` / the triage path reproduces or explicitly records
   "not reproducible" and checks for an existing task before a role may flip to
   `ready-for-agent`; briefs name contracts, never paths. Home: ADR-086 §3's role derivation
   gains a precondition.
3. **QA-plan brief** (S3): the wave-ship close-out emits a step-by-step QA plan from the wave's
   commits as a `kind: review` task tagged human; the cockpit digest links it; it is completed
   (leaves context) when walked. Home: epic-drain §Merge / wave ship.
4. **File-size gate** (S4): a pre-commit lint refuses a diff that pushes a file past 1,000
   lines without an override tag. Home: `validate.sh` fast path + pre-commit.

Habits (S5–S8) are folded into existing tasks' context (t-3012, t-2984, t-2981, decompose
phase) and into the delegation-routing rule the operator asked for today (cheaper models for
read-and-extract agents; smartest model for the interview).

## Consequences

**Positive.** One pin, one bump procedure, one set of kill proxies for five organs. The two
disciplines that most directly carry his implementation quality (proven red; evidence at the
merge valve) land as vendored artifacts with a human valve on every bump, not as prose
re-implementations that drift silently. The merge valve stops receiving conflicted branches.

**Negative (accepted).** Five organs is five `redirect-check.md` files to re-verify per bump;
until the third bump this is hand labour. `pr` adds a model-invoked skill to every session's
description budget (the `context-budget.sh` pre-commit hook is near capacity — t-2836's note;
the adapter description must be short). Holding `retro` means the environment-lens gap stays
open for at least one more quarter.

**Risk retained.** A bump that changes an organ's *shape* (a renamed step the adapter's
remap depends on) is caught only by the `redirect-check.md` re-verification — a human
reading, not a test. Mitigation: each spec names the upstream step headings its adapter
depends on, so the diff reviewer knows what to look for.

## Non-Actions

| Not doing | Why |
|---|---|
| Vendor `implement-spec` | brana's runner is the thing he ranks above it; no Epic-ring state in his version to adopt |
| Vendor `retro` now | home and human position undecided (D5) |
| Build the ADR-084 §1 instruments | two bumps are not a trend; third bump re-opens |
| Create `docs/domain/glossary.md` here | t-3013's discipline decides its shape; D7 maps to what exists |
| Contribute fixes upstream | closed by his `new-skills.md`; vendoring is the only relationship |
| Per-organ pins | one gauge number beats three; organs that must lag get reverted, not pinned apart |

## References

- [ideas/pocock-v13-adoption.md](../../ideas/pocock-v13-adoption.md) — the shaped idea, ring-fit table, penciled plan P1–P6
- [research/2026-10-07-pocock-recheck.md](../../research/2026-10-07-pocock-recheck.md) — §2 findings, §3 follow-ups, §3a diagrams
- [ADR-084](ADR-084-upstream-skill-band-vendored-pocock-skills.md) §1–§3 (mechanism), §7 (proxies), §7a (pilot outcome)
- [ADR-061](ADR-061-goal-integration-three-primitive.md) §4 invariants 2 and 3
- [ADR-085](ADR-085-skills-as-stations-no-atom-schema.md) D4, D6
- `system/skills/diagnose-hard-bug/SKILL.md`, `system/skills/two-axis-review/SKILL.md`, `system/skills/provisioning-wizard/SKILL.md` — the three live adapters this ADR's pattern is read from
- upstream: `mattpocock/skills` `SCOPE.md`, `.out-of-scope/{new-skills,mainstream-issue-trackers-only,subagent-recursion}.md`, release v1.3.1

## Challenge record

Pending. One context-isolated `/brana:challenge` pass on this ADR before acceptance; findings
and their disposition recorded here.
