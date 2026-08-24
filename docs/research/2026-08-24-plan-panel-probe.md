# PLAN-panel probe — retrospective measurement (t-3156)

> Spike deliverable, 2026-08-24. Guide L7 #4. Methodology mirrors the JUDGE-panel probe
> [2026-08-14-judge-panel-probe.md](2026-08-14-judge-panel-probe.md) (t-2887): retrospective,
> blind, decision rule pre-registered before scoring.
> Question: on ~6 past decompositions that became real task trees, would a diverse PLAN panel
> (MVP-first / risk-first / user-first) have made **material** tree changes that the recorded
> single-pass planning (planner + sprint-contract challenger where present) missed — validated
> by what execution later proved?

## Verdict: GO — narrow, with a mandatory scope cut for t-2896

**2 of 6 decompositions carry a validated material miss; 1 of those is a clean
escaped-defect-class catch** (t-2284: the missing read-path consumer sweep that later cost 5–6
follow-up fix tasks, having escaped a 2-iteration plan challenger, the evaluator, AND the
post-build challenger). The pre-registered GO bar (≥2/6 validated material misses) is met —
narrowly, and the qualifier section below is part of the verdict, not a footnote.

## Pre-registered decision rule

GO requires ≥2 of 6 decompositions to each show ≥1 **validated material miss**: a panel-proposed
tree change (add/remove/split/reorder/rescope a child) that (a) the recorded plan-time process
did not make, and (b) execution later proved necessary (escaped defect, mid-build re-decomposition,
follow-up rework tasks). Bar set above t-2887's ≥1 because the competing lever — decomposition
discipline per ADR-086 §1 — already exists and panel cost recurs per plan.

## Method

- **Corpus:** 6 completed M/L decompositions with full execution records:
  t-3151 (platform adapter, 14 children), t-2857 (stacked verdict, 6), t-2826 (loops library, 7),
  t-2812 (ac-approve verb, 6), t-2630 (validate remedies, 9), t-2284 (backlog-v3 schema, 10).
- **Blinding:** per tree, a plan-time-only snapshot (parent subject/description + child
  subjects/descriptions/efforts/blocked_by; context/notes/status stripped) handed to a fresh-context
  subagent forbidden from reading the repo, backlog, or git. One agent simulated all three lenses
  (hand-sim fidelity per task scope, not the full 3-independent-agent wiring).
- **Ground truth:** execution records read only after panels ran — parent context/notes
  (challenger verdicts, mid-build corrections), child notes, and follow-up tasks citing the parent.
- **Scoring:** each MATERIAL panel proposal → VALIDATED (execution proved the tree wrong there) /
  PARTIAL (right zone, defect real, but caught by an existing later rung or proposal non-specific) /
  NOT VALIDATED (no execution pain) / RE-CATCH (plan process had already decided it — usually
  visible only in the sprint contract my snapshot stripped).

## Results per decomposition

| Tree | Panel material proposals | Validated | Ground-truth residual the panel had to beat |
|------|--------------------------|-----------|---------------------------------------------|
| **t-2284** (L, schema migration) | 7 | **1 CLEAN**: "no child audits read-path consumers of the retired level/epic fields outside the sealed write surfaces — add a repo-wide consumer sweep subtask." Execution: t-2375/t-2377/t-2381/t-2388/t-2472 (+t-2439 write-path cousin) all filed post-completion as escaped rework. Escaped 2-iteration plan challenger, evaluator PASS, post-build challenger PROCEED. | Read/serialize stragglers of retired fields (5–6 fix tasks) |
| **t-2857** (M, gauge/valve) | 4 | **1 QUALIFIED**: panel's two structural proposals (heuristic-parity golden fixture; gauge/gate must share one implementation before human exposure) both target gauge-vs-gate divergence — the zone where execution found the real frozen-criteria-snapshot gap that forced a mid-build rescope of t-2869 (--criteria-json). Proposal was material and zone-correct; not the specific criteria-source question. Panel MINOR on worktree-resolution fragility also validated as real friction. | Frozen-criteria gap; integration-smoke gap (t-2871's 2 live-only bugs); t-2879 bootstrap lib/ deploy SHIP-BLOCKER — the last two missed by the panel |
| **t-3151** (M, adapter) | 7 | **1 PARTIAL**: "discovery path (who creates the UrlEntry / calls ingest) is unowned by any child" — the event-log discovery path is exactly where the sev-4 raw-key identity bug lived. But the rung-1/2 judge ladder caught that pre-merge; panel value would have been an earlier catch, not an escape prevention. Migration-race concern partially validated (re-run-at-ship note). | 2× second-variant raw-key siblings + lock starvation — all caught by the existing escalation ladder before merge |
| **t-2812** (M, verb) | 4 | 0. Panel's headline finding (no consumer child) was a re-catch of a decision recorded in the stripped sprint contract (consumer = t-2813, ADR-079). Its MINOR (approve→edit→approve interaction) matched the post-build challenger's sev-1/2 observation — same-rung re-catch. | None — clean tree; the one structural gap (born-approved bypass) was caught pre-code by the three-write-paths survey |
| **t-2630** (M, remedies) | 7 | 0. The real residual (second PYEOF heredoc syntax variant, sev-4 at BUILD challenger) is uncatchable without repo access — structurally outside a tree-only panel's reach. Several panel findings were re-catches of ACs living in stripped child contexts. | Heredoc second-variant regex gap (repo-access-only) |
| **t-2826** (M, catalog) | 6 | 0. Both headline findings (/loop + discover wiring unowned; lint enforcement point) were deliberate cuts recorded in the stripped sprint contract. The one validated tree defect (t-2933's AC demanding a rewrite of an accepted ADR — execution had to deviate) lived in the stripped AC text, invisible to the panel. | t-2933 AC vs ADR-immutability (visible only in stripped AC); sibling-field gaps (repo-access-only) |

**Measured rates:** clean validated miss 1/6 trees; validated incl. qualified 2/6; zone-hit 3/6.
Raw material proposals: 25 across 6 trees → **~12% validated precision** (~2–3/25); the bulk of
false positives were re-catches of sprint-contract decisions my blinding stripped — a real
plan-time panel would see the contract, raising precision but converting those findings to noise
of a different kind (re-litigating decided cuts).

## Cost

6 hand-sim agents ≈ 482K subagent tokens ≈ **80K/tree** for this thin form. A wired t-2896 panel
(3 independent lens agents + repo access + verification pass, per the judge-probe shape) lands at
the 2.5–3.5× anchor vs the single sprint-contract challenger (~50–150K/decompose). Yield at that
spend, extrapolated from this probe: ~1 escaped-class catch per ~6 M/L decompositions, plus
earlier-catch value on defects the rung ladder currently gets pre-merge.

## Qualifiers (part of the verdict)

1. **Both validated hits are one finding class:** "a changed identity/contract needs an exhaustive
   consumer/sibling sweep child" — already stored as memory patterns
   (`pattern_second-variant-audit-every-raw-consumer`,
   `pattern_tightened-precondition-must-sweep-concrete-instances`,
   `pattern_sibling-field-validation-gap`). A **zero-cost discipline lever exists**: make
   "does any child change an identity, key, field, or contract? then a consumer-sweep child is
   mandatory" a DECOMPOSE checklist line. This probe cannot distinguish "panels are worth 2.5–3.5×"
   from "one checklist line captures most of the measurable value." The discipline lever should
   ship regardless of t-2896 (filed as a follow-up; see ANSWER).
2. **Where the hits were:** the clean catch was on the **L-effort migration** tree; the M trees
   with tight sprint contracts (t-2812, t-2630, t-2826) yielded zero. Arm the panel by scale and
   class — L-effort or identity-migration decompositions — not per-plan (consistent with t-2894's
   opt-in/threshold-armed contract and ADR-082's ladder).
3. **Repo access is load-bearing:** 2 of 6 ground-truth residuals were uncatchable from the tree
   alone. A wired panel must get repo read access (t-2887 already showed how to blind it from
   task notes), or it forfeits the second-variant class — the class it is best at.
4. **Verification stage is mandatory:** at ~12% raw precision, unverified panel output would bury
   the human valve; same conclusion as t-2887 ("verification is not optional").

## Consequences (executed per AC)

1. **t-2896 unblocked** (blocked_by t-3156 cleared), context appended with this verdict + the
   scope cut: arm only for L-effort / identity-migration decompositions; repo access with
   note-blinding; verification stage mandatory; disagreement-surfacing aggregation per Round 5.
2. **Discipline follow-up filed** independent of t-2896: DECOMPOSE checklist line — identity/contract
   change ⇒ mandatory consumer-sweep child (closes the measured escaped class at zero recurring cost).
