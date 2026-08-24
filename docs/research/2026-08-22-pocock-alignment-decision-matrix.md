---
title: Pocock-alignment decision matrix — L3 CYCLE mechanisms
status: draft — feeds the-brana-guide.md L3 walk
created: 2026-08-22
task: t-2490
related: docs/ideas/the-brana-guide.md (L3), docs/research/2026-08-13-matt-pocock-skill-system.md, docs/research/2026-08-18-pocock-methodology-synthesis.md (worktree thebrana-t-2837), docs/research/2026-08-14-multiagent-orchestration-lessons.md, docs/ideas/loop-task-multiagent.md
---

# Pocock-alignment decision matrix — L3 CYCLE mechanisms

Decision: for each concrete mechanism in brana's v3 loop/wave/backlog design that has a Pocock-comparable
counterpart (or a confirmed absence of one), choose ADOPT (his practice) / KEEP (brana's current practice) /
ADAPT (hybrid) / ADD (neither has it, build new). Scored per operator's actual context: solo/small-team,
runs real unattended production loops today (knowledge-pipeline, link-pipeline crons), does paid client work
(quoting/billing), cares about token cost and legibility, has already suffered concurrency-race incidents
(t-2216/t-2206).

## Criteria and weights (operator's judgment call, not objective)

| Criterion | Weight | Why this weight |
|---|---|---|
| Business value / capability unlocked | 25% | Per the corrected evaluation rule (memory `feedback_backlog-field-usage-vs-feed-mechanism`) — judge by what it enables, not usage % |
| Security & safety (unattended blast radius) | 20% | Real unattended crons run today against live client/personal systems — this isn't hypothetical |
| Efficiency (token/compute cost) | 15% | Confirmed 3–10× multi-agent tax; cost-consciousness already a standing rule (context-budget.md) |
| Legibility / opacity (Pocock's own stated bar) | 15% | His actual critique target is process opacity, not verification depth — the one criterion that's *his*, not ours |
| Speed / velocity to ship and iterate | 15% | Solo-operator throughput matters; simplicity is itself a speed lever per Pocock's thesis |
| Scalability (holds at ~2,845 tasks and growing) | 10% | brana already operates at a scale with no confirmed Pocock precedent |

Scores are 1–10 (10 = best fit for this operator), weighted sum out of 10. These are my judgment calls,
not measured data except where a row cites a specific incident or probe result — treat this as a
structured opinion, not ground truth.

## Matrix

| # | Mechanism | Pocock's practice (cited) | A: Pocock | B: brana | Verdict |
|---|---|---|---|---|---|
| 1 | Loop runtime (`/loop`, drain-loop/epic-drain, unattended) | "the loop is a human habit" — no runtime, human/`claude --bg` grabs a ticket by hand | **5.45** | **7.55** | **KEEP brana** — this operator already runs real unattended crons; the human-habit model loses that value entirely |
| 2 | Wave-level parallelism (independent tickets → concurrent agents) | `to-tickets` emits a parallelizable DAG — "two tasks with no shared dependency, grabbable by separate agents" | **7.25** | **5.45** | **ADOPT** — build t-2889; his frontier rule is also stricter (see #10) |
| 3 | Task-level JUDGE panel (hive-mind/verify-findings at build gate) | none — human code review only | **6.75** | **6.85** | **CLOSE CALL (1.5% gap)** — lean KEEP brana (measured: 4 verified misses / 6 diffs, 2.5–3.5× cost, escalation-gated not standing); sensitive to how much you weight legibility |
| 4 | Task-level PLAN/DECOMPOSE panel (hive-mind at decomposition) | none — single-pass `to-tickets` generation, no adversarial pass | **7.35** | **7.25** | **CLOSE CALL** — raw score slightly favors Pocock's simplicity despite this being multi-agent's "legitimate win zone" per research; genuinely too close to call from criteria alone |
| 5 | `ac_state` approval gate | none — single readiness label, no approval workflow | **5.8** | **6.8** | **KEEP brana** — real unattended-loop safety value; 0.8% usage is early-stage load-bearing infra, not overbuilt (per L2.4's corrected-usage-lens finding) |
| 6 | Leases (concurrency control on wave pull) | none — single-threaded, no lease needed | **5.1** | **7.25** | **KEEP brana**, and becomes a *dependency* of #2's ADOPT — parallel pulls need leases or you reproduce t-2216/t-2206 |
| 7 | Dead-letter handling | `wontfix` — human-only classification | **5.3** | **7.65** | **KEEP brana** — t-2587 (LinkedIn-miss starvation) is a real, already-logged incident of exactly the failure mode automatic dead-letter prevents |
| 8 | Beat record (per-iteration structured log) | none — decisions are markdown docs referenced by the ticket, no schema | **7.35** | **5.65** | **ADOPT** (already decided at L2.4 for the `log` field via t-3008; this generalizes to L3.1's "record" column and L3.5 directly — don't re-litigate) |
| 9 | Cross-skill readiness/handoff state | single 5-role field: `needs-triage→needs-info→ready-for-agent→ready-for-human→wontfix` | **7.95** | **4.65** | **ADOPT**, decisively — clearest win in the matrix; resolves the confirmed gap (brainstorm's exit-router is conversational, can't hand off headless). Gated on t-2834 per existing plan |
| 10 | Gate graph / `blocked_by` in the pull frontier | frontier = open ∧ **unblocked** ∧ unclaimed — his loop is *stricter* than brana's today | **8.25** | **4.1** | **ADOPT**, largest margin in the matrix — fixes a confirmed bug (`pattern_wave-pull-ignores-blocked-by-ordering`), not a style choice. This is L3.3 — amend ADR-079 §2 |
| 11 | Task = agent's unit vs wave = human's unit (bifurcation) | one ticket is *both* simultaneously — no split; "task = one fresh context window" cut rule (already adopted, ADR-086/t-2980) | **7.35** | **7.05** | **OVERRIDE to KEEP brana** — raw score favors Pocock, but client quoting/billing is a hard requirement his tool was never scoped for at all (Bucket 2). See note below — the 6 generic criteria miss this |
| 12 | Fresh-context-per-pull default | implicit in every Ralph-loop iteration (fresh Claude invocation) | **9** | **9** (t-2982) | **ADOPT** — no real tension, already the direction; confirms rather than decides |

## Note on row 11 — a matrix limitation worth naming

Row 11's raw weighted score slightly favors Pocock's unified ticket, but none of the six generic criteria
capture "does this support billing a client for a defined chunk of work" — a requirement this operator
actually has (paid client engagements under `clients/`) that Pocock's tool was never scoped to solve at all
(no quoting, no client-delivery concept in his system). This is exactly the Bucket 2 argument the guide's
L3 standing note already made, now visible as a **must-have filter** the weighted matrix can't express on
its own — per the skill's Method 3 (must-have vs nice-to-have), a hard business requirement should filter
before scoring, not just add to the weighted sum. Treat row 11 as **KEEP brana**, not a close call.

## Sensitivity summary

Gaps, recomputed and corrected (an earlier draft of this section mis-grouped #2 and #8 — fixing here):
#1 2.10 · #2 1.80 · #3 0.10 · #4 0.10 · #5 1.00 · #6 2.15 · #7 2.35 · #8 1.70 · #9 3.30 · #10 4.15 · #11 0.30 (overridden) · #12 0.

- **Decisive (>1.5pt gap, not sensitive to a plausible weight tweak):** #1, #2, #6, #7, #8, #9, #10 — the
  operator's actual unattended-production context makes brana's heavier machinery earn its keep on #1/#6/#7;
  #2/#8/#9/#10 are clean ADOPTs (two of them, #9/#10, fix confirmed gaps/bugs, not just style preference).
- **Thinner margin, same qualitative direction (~1pt gap):** #5 (`ac_state`) — the narrowest KEEP-brana
  call in the matrix by the numbers, though the qualitative case (corrected usage-lens finding, real
  unattended crons) is strong regardless of the exact score.
- **Genuinely close (<0.5pt gap):** #3 (JUDGE panel) and #4 (PLAN panel) — these are legitimately your call,
  not mine; the criteria weights you'd need to swap to flip them are legibility vs. business-value/security.
- **Override case:** #11 — the matrix's own generic criteria miss a hard business requirement (quoting);
  don't let the raw score decide this one.

## Recommended action order

1. **#10 first** (largest margin, fixes a live bug) — amend ADR-079 §2, resolves L3.3.
2. **#9** once t-2834 lands (already gated) — resolves L2.2b and the L3 standing-note's Bucket-1 candidate together.
3. **#2 + #6 together** (parallelism needs leases to be safe) — build t-2889 with leases from day one, don't ship parallel-without-leases even temporarily.
4. **#8** — confirm L3.1/L3.5 inherit L2.4's already-locked `log`-as-markdown-doc resolution rather than re-debating.
5. **#3, #4** — your call; if forced to pick, keep #3 (JUDGE, measured evidence exists) and reconsider #4 (PLAN, no measured evidence yet, matches Pocock's simpler single-pass model) unless you want to run a probe on #4 the way #3 already got one.
