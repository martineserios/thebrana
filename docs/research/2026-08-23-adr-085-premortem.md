# Pre-mortem: ADR-085 (skills as stations, no atom schema) — before landing

**Date:** 2026-08-23 · **Task:** t-2490 · **Method:** Klein prospective hindsight (pre-mortem skill)
**Input:** [ADR-085](../architecture/decisions/ADR-085-skills-as-stations-no-atom-schema.md) (Proposed) + [skills-loops-graphs.md](../ideas/skills-loops-graphs.md) + guide walk L0–L6 outcomes ([the-brana.md](../architecture/the-brana.md))
**Feeds:** the operator-run `/brana:challenge --deep` on ADR-085 (this doc is input to it, not a substitute for it).

**Scenario:** It is 2027-02. ADR-085 was accepted, t-2490 closed. Six months on, the
skills-as-stations decision has failed — the duplication it named is back, the deferred
items never resolved, and a session is re-litigating the atom schema from scratch.
Looking back, it's obvious why.

## Failure reasons (clustered), fact-checked against the repo 2026-08-23

### EXECUTION / LANDING

**F1 — Follow-up #5 was never filed. [CRITICAL — CONFIRMED ALREADY TRUE]**
ADR-085 Consequences claim "follow-ups = filed"; its list maps to t-2981–84. But #5
(single-source the drifted judgment organs — verdict rubric, repair loop, corroboration
rule — and fix the CALIBRATION↔verify-findings divergence) has **no backlog task**
(searches 2026-08-23: zero hits; t-3010 covers only pair C/TDD). The D4 "wiring" half of
the decision — the half motivated by pain that is *live today* — silently fell out of the
tracker. Pair A duplication verified still present post-merge
(`verify-gates.md:101` ↔ `build-evaluator.md:57`).
*Nuance (stale claim in the ADR):* the js side has been partially hardened since 08-18 —
`verify-findings.js` now defaults voters to 3 (odd → ties impossible) and `UNVERIFIED` is
a deliberate, documented state (t-2149). The **contradiction half of #5 is smaller than
the ADR states; the organ-duplication half is unchanged.** The ADR text should be
corrected when landed, or the challenge will flag its own evidence as stale.
Likelihood: happened · Impact: H · Detectability: never (silent).

**F2 — Two ADR-085s on dev. [MANAGEABLE]**
Worktree `../thebrana-t-2980` carries `ADR-085-wave-as-human-unit-pocock-ticket-shape.md`;
the renumber to 086 (t-3030, D2) is pending though now unblocked (t-3026 done). If either
branch merges before the renumber, dev holds two ADR-085s and the-brana.md's
"ADR-085→086 (t-2980, renumber D2)" row points at ambiguity.
Likelihood: M · Impact: M · Detectability: early.

**F3 — Accepted-but-never-challenged, or Proposed-forever. [MANAGEABLE]**
`/brana:challenge --deep` is operator-gated (`disable-model-invocation`). If the operator
never runs it, t-2490 either stays open indefinitely or closes with the ADR unchallenged
while downstream tasks (t-2981, t-3010–13) build against it. Same block t-2837 hit.
Likelihood: M · Impact: M · Detectability: early.

### ASSUMPTION FAILURES

**F4 — The whole D6 evidence chain hangs on t-2834, which nobody is driving. [CRITICAL]**
t-2834 is `pending`, not started, P-unowned. Gated on it: t-2981 (second pilot),
readiness-state resolution (L2.2b/L3), t-3021 (rooms/hands), the station-admission
checklist, and every "deferred, earns itself via D6" row in the Non-Actions table. If
t-2834 stalls, all deferred items quietly become permanent non-decisions — and in six
months someone reopens the atom schema from scratch, which is precisely the churn ADR-085
exists to prevent. The ADR itself names this risk ("Risk retained") but assigns no owner,
date, or tripwire.
Likelihood: H · Impact: H · Detectability: late.

**F5 — D3 has no enforcement point. [MANAGEABLE]**
"New/adapted skills are two-tier, no AskUserQuestion on the main path, schema'd return as
a Workflow node" governs skill *authors*, but nothing reads it: no validate.sh check, no
authoring checklist, no hook. Memory pattern `gate-armed-by-the-party-it-constrains`
predicts the outcome: new skills ship non-conforming and the ADR governs nothing.
Likelihood: M–H · Impact: M · Detectability: late.

**F6 — The "manifest after a third binding" trigger lives only in ADR prose. [MONITOR]**
Nobody counts bindings. When the third binding arrives, the field-repetition evidence
exists but no one is watching for it, so either the manifest never gets written (drift
resumes) or it gets written early by someone who never read D2.
Likelihood: M · Impact: L–M · Detectability: never.

### EXTERNAL / DRIFT

**F7 — Post-challenge amendments strand the guide-walk references. [MONITOR]**
the-brana.md carries 4 ADR-085 references keyed to specific decision wording (D2 owner
row at :133, verdict row at :213, renumber row at :219). If the challenge amends
D-numbers or verdicts, those rows go stale — reintroducing the drift the guide walk
existed to kill. The 136-commit dev merge (done 2026-08-23, clean) widened this surface.
Likelihood: M · Impact: L · Detectability: early (grep).

## Risk matrix

| # | Failure | Likelihood | Impact | Detect | Priority |
|---|---------|-----------|--------|--------|----------|
| F1 | Follow-up #5 unfiled; ADR evidence partially stale | happened | H | never | **CRITICAL** |
| F4 | t-2834 keystone stalls; deferred → permanent | H | H | late | **CRITICAL** |
| F2 | Two ADR-085s on dev | M | M | early | MANAGEABLE |
| F3 | Challenge never runs | M | M | early | MANAGEABLE |
| F5 | D3 unenforced | M–H | M | late | MANAGEABLE |
| F6 | Third-binding trigger unwatched | M | L–M | never | MONITOR |
| F7 | Post-challenge doc drift | M | L | early | MONITOR |

## Prevention plan

1. **(F1)** File the missing follow-up-#5 task now — organ single-sourcing per the L2.3
   grain-file decision (rubric → `system/agents/build-evaluator/rubric.md`; hive-mind and
   repair-loop organs stay `_shared/`), tagged `t-2490-followup`. Before landing, amend
   ADR-085's Context/#5 to the current facts (voters=3 default, UNVERIFIED deliberate).
2. **(F2)** Sequence: t-3030's renumber (or t-2980's branch renaming its own file) merges
   **before or with** whichever of the two ADR branches lands second. Tripwire at merge:
   `ls docs/architecture/decisions | grep -c "ADR-085"` must be 1.
3. **(F4)** At t-2490 close, force an explicit operator decision on t-2834: priority + a
   review date. Tripwire: t-2834 still `pending` at the next weekly review → either
   promote it or explicitly demote the D6 chain (recorded, not silent).
4. **(F3)** Tripwire: if the challenge hasn't run within 14 days of this doc, surface at
   weekly review — options: run it then, or Accept-with-note recording that the deep
   challenge was waived (operator call, recorded in the Challenge record).
5. **(F5)** Add one D3 conformance line to the skill-authoring surface (candidates:
   validate.sh check or `/brana:acquire-skills`/discover checklist) — fold into t-3030's
   housekeeping or file as S. Decision at close, not silently dropped.
6. **(F7)** Post-challenge, sweep `grep -rn "ADR-085" docs` in the same commit as any
   amendment. (F6 accepted as residual: note the binding-counter in ADR-085's follow-up
   list when amending per item 1.)

## Verdict

**PROCEED with conditions** — the design content (D1–D6) surfaced no new architectural
failure mode this exercise could kill; the corroborated peer synthesis and the guide walk
already stress-tested the shape. The failure modes are all *process*: an unfiled
load-bearing follow-up, stale evidence in the ADR text, an unowned keystone dependency,
and a numbering collision. Items 1–2 should be done **before** the operator runs
`/brana:challenge --deep`; items 3–5 are close-time decisions.
