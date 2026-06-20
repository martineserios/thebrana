# Feature Spec — Native Cross-Model Consensus Primitive

**Task:** t-2143 · **Status:** DESIGN ONLY (no implementation) · **Date:** 2026-06-20
**Basis:** [ADR-059](../decisions/ADR-059-multi-agent-substrate-selection.md) · `.claude/workflows/` (hive-mind, verify-findings, sweep)

## Problem

ruflo advertised `coordination_consensus` / `hive-mind_consensus` — but under the subscription they run with `totalNodes:1` (a self-vote) — hollow (ADR-059). brana has three real native blocks (hive-mind, verify-findings, sweep), but none provides **Byzantine-inspired agreement across genuinely independent voters** for a single high-stakes decision where the cost of a wrong "yes" is large (e.g. "is this irreversible migration safe to run?", "should the autonomous runner be allowed to touch this surface?").

## Why a distinct primitive (boundary — do not merge)

| Block | Question | Output |
|-------|----------|--------|
| **hive-mind** | "what's the best answer to X?" | one synthesized answer + adjusted confidence |
| **verify-findings** | "which of these findings hold, at what severity?" | per-finding hold/severity (judge panel) |
| **sweep** | "find ALL of Y" | clustered, verified findings |
| **consensus (this)** | "do independent voters AGREE on a single yes/no, enough to act?" | a binary GO/NO-GO + the agreement margin + dissent record |

Consensus is **decision-gating**, not answer-finding or finding-verifying. It exists to make a *commitment* safe, so its bar is agreement strength, not best-answer synthesis.

## Design

```
consensus({ proposition, voters=5, threshold=0.8, models=[...] })
  1. Convene N INDEPENDENT voters — diverse lenses AND, where possible, diverse MODELS
     (the one place cross-model diversity earns its cost: a real second architecture, not
     N copies of one model agreeing with themselves — ADR-059's agy-as-second-opinion logic
     generalized). Each votes GO/NO-GO with a reason, blind to the others.
  2. Byzantine tolerance — require a SUPERMAJORITY (default ≥ 80%), not a bare majority, so a
     minority of faulty/over-eager voters cannot carry a GO. Ties and sub-threshold → NO-GO
     (fail safe: the absence of strong agreement is a NO).
  3. Record dissent — every NO-GO reason is surfaced (a single sharp objection often matters
     more than the count). NO-GO with a strong reason routes to a human.
```

**Fail-safe default:** uncertainty resolves to NO-GO. A consensus primitive guarding a commitment must never let "couldn't decide" read as "yes."

## Reuse, don't reinvent

Build on the existing Workflow runtime + the `parallel()` fan-out pattern from hive-mind/verify-findings. Cross-model diversity uses `agent(..., { model })`; when only one model tier is available, fall back to lens-diversity with an explicit note that architectural diversity was unavailable (no theater — say what you actually got). The graceful-degradation discipline from t-2149 applies: a voter that fails to return a structured vote is dropped, not counted as GO.

## Open questions

1. Where consensus gates in practice (migration runner? Stage 4 graduation? `/brana:ship`?) — pick the first real caller before building; don't build speculatively (ADR-059 doctrine).
2. Model-diversity sourcing under the subscription (which model tiers are independent enough to count as Byzantine-distinct).
3. Voter count / threshold calibration against a real high-stakes decision.

## Out of scope

Implementation — built when a real decision-gate needs it (see [substrate-end-state](../substrate-end-state.md)).
