---
title: Brana v3.2 challenge — fresh adversarial review
date: 2026-07-21
target: docs/ideas/brana-v3-redesign.md (draft v3.2)
prior: docs/reviews/brana-v3-challenge-2026-07-19.md · docs/reviews/backlog-v3-schema-challenge-2026-07-20.md
verdict: PROCEED WITH CHANGES
---

# Brana v3.2 challenge — fresh adversarial review (2026-07-21)

A second-pass review of `brana-v3-redesign.md` **as it stands at v3.2**. The 07-19 challenge
reviewed v3.0; the 07-20 challenge reviewed the schema elaboration. This pass finds holes
those two did **not** raise, and deliberately **excludes** everything they settled:

> **Not re-raised (settled 07-19 / 07-20):** Routines premise · write-path sealing · `tags`
> polymorphism · AC-coverage numbers (canonical: ~1.8%, 38/2,156) · ADR-060 amendment framing ·
> goal-completion.sh guard-by-guard migration · wave-1 cap split · honest L3 labels · lazy/on-touch
> migration · 3-verb CLI · outcome-ledger over approve-clicks.

## Findings

### 1 — HIGH · The soak gate is unreachable at the design's own stated throughput
Success metric = **≥1 loop-driven task/day** (solo), and the doc frames "L2 is where most work lives,
*permanently* — a feature." But wave-5 graduation needs **≥50 outcomes / ≥2 weeks**, then a per-*shape*
rule table (≥95% merged-clean). At 1 task/day, 2 weeks = 14 outcomes across **all** shapes; a single
fine-grained shape (kind,effort,tags,file-surface,AC) essentially never accrues enough runs. Either shapes
must be coarse (auto-demote becomes the only real guard) or **L3 is decorative** for a solo operator — yet
wave 5 is specced as delivering it. Decide: aspirational or dated. → **t-2285**

### 2 — HIGH · The compute chain moves the bottleneck; it doesn't remove it
Principle 7 / L6: agy exhausts → switch to Claude SDK pool → "queues always drain, never defer to a quota
reset." The fallback pool is the **same exhaustible subscription** — this session's startup reminder:
*"Extra-usage disabled (org_level_disabled_until)… fail around the 200k-token mark."* When agy is dry
(daily, by their own diagnosis) **and** the Claude pool hits its wall, the worker defers-to-reset again —
the exact deadlock the redesign set out to fix, one engine later. Needs a hard per-night token ceiling +
graceful partial-drain + resume, not an unbounded-Claude assumption. → **t-2286**

### 3 — HIGH · The observe-invariant contradicts LEARN's actual job
Principle 6: "every loop starts observable" — read + ledger-write only, test proving **no task/git/reminder
mutation**. But wave-2's LEARN worker's entire output is **writes to memory/patterns** — mutations to the
store every other loop reads. Either the invariant silently excludes memory writes (narrower than the safety
claim implies) or LEARN can't ship observe-first. Unreconciled, and on the critical path (LEARN is the one
loop wave 2 ships). Resolvable by generalizing the `ac_state:proposed` **real-but-inert** write pattern
(t-2283): writes that gate nothing until human promotion. → **t-2287**

### 4 — MEDIUM · "Deletes ≥ adds" is a non-negotiable gate the docs already contradict
Main doc asserts "deletes ≥ adds" as a **non-negotiable** per-wave gate. The schema doc says it holds for
**fields, not code surface**, and needs a cost-baseline spike. Two live docs in one epic disagree on whether
the gate is measurable; "surface" is never defined with a unit, so it self-certifies green every wave. Define
the unit and accept it may fail some waves, or demote it from "non-negotiable" to "directional." *(Mitigated
in the MVP by demand-driven field adds — see t-2283.)*

### 5 — MEDIUM · The north star is deferred twice; v3 can "finish" without it
The self-evolving pipeline (skills-as-loops' task-as-workpiece model) is deferred to *its own* final wave,
and skills-as-loops is blocked (t-2278) behind the schema landing. The actual north-star loop is one-wave-away
behind a thing that's one-wave-away — waves 1–5 can all ship without it. Define what "v3 done" means: the L2
cockpit (achievable) or the autonomous pipeline (perpetually deferred)?

### 6 — LOW-MED · Sequencing: ADR-065 elevates a resolver t-2281 calls broken
ADR-065 makes `epic` the sole hierarchy top + adds `active_epic` pointer semantics; t-2281 documents that
resolver as **cross-project-leaky**. The fail-loud assertion catches divergence but not the scoping bug. The
schema-landing wave must be `blocked_by t-2281`. → captured: **t-2284** (`blocked_by t-2281`).

## Verdict — PROCEED WITH CHANGES

Architecture sound; discipline (observe-invariant, ledger, wave contract, adopt-don't-build) is a real bar.
But three load-bearing claims don't survive contact: the graduation gate is unreachable at the stated
throughput (#1), the compute chain's "never defer" guarantee is false under the current subscription (#2),
and the ladder's first rung forbids exactly what its first real loop does (#3).

**What would most move confidence:** (a) an honest reachability statement on L3 at solo throughput; (b) a
hard token-ceiling + partial-drain-resume worker design; (c) one sentence reconciling observe-invariant with
memory-writing loops.

## Disposition
| # | Sev | Task |
|---|-----|------|
| 1 | HIGH | t-2285 |
| 2 | HIGH | t-2286 |
| 3 | HIGH | t-2287 |
| 4 | MED | folded into t-2283 (demand-driven adds) |
| 5 | MED | open question for the v3 epic plan |
| 6 | LOW-MED | t-2284 (blocked_by t-2281) |

> The MVP that came out of this review (the `ac-propose` loop + forward-only `ac_state` slice, t-2283)
> deliberately sidesteps #1/#2/#3: it delivers value at L1 (no soak gate), runs local/cheap with a hard cap
> (no compute chain), and writes only inert `proposed` state (no observe-invariant breach).
