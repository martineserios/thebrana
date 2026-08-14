---
title: /goal integration — three-primitive composition
status: draft
created: 2026-06-21
task: t-2194
---

# /goal integration — three-primitive composition

> Brainstormed 2026-06-21. Work in progress. Design-only (t-2194).

## Problem

The loop-native redesign designed `/loop` (foreman) + `Workflow` (crew) but never
placed the third CC-native primitive, `/goal` (in-session iterate-until-condition).
Finding 3's mapping table has two rows; this design adds the third and says where
`/goal` fits, which skills gain a `/goal` loop, and how it terminates on
machine-verifiable state.

## The composition model (the core finding)

The three primitives split by **what they do to a gate**:

- **`/loop` = POLL across tasks** — the only one allowed to span human gates, because it
  doesn't cross them: it parks and hands back to the human. (Session / foreman level.)
- **`/goal` = ITERATE within one gate-free span** until an observable `done` predicate
  holds. (Per-task / per-skill-phase level.)
- **`Workflow` = FAN-OUT once** inside a single attempt. (Crew level.)

## Eligibility criteria — where `/goal` is allowed to live

Two hard filters, three soft:

| # | Criterion | Type |
|---|-----------|------|
| C1 | Machine-verifiable stop signal at this grain (exit code / AC / validate.sh) | HARD (LoopTrap P5/P7) |
| C2 | Span is gate-free (no human gate inside it) | HARD (ADR-050: never auto-cross a gate) |
| C3 | Bounded iteration (≤3 auto-advances, cost-capped) | soft (ADR-050 cap) |
| C4 | Survives context (short spans favored — rot/compaction) | soft |
| C5 | Composes with built `/loop`-foreman + `Workflow`-crew | soft |

The **session level fails C2** (crosses N merge gates) → that level is `/loop`'s job, not
`/goal`'s. This is the clean three-way split.

## Architecture — one primitive, many bindings

Not N features. **One `/goal` primitive parameterized by a stop-condition contract**
(from t-1992 step-state: `{checkpoint, next_step, gate_pending}`), plus a grep-able list
of skill spans that declare a span + observable done-signal. A skill "gains a `/goal` loop"
by declaring one thing; new bindings are cheap.

## v1 bindings (selected 2026-06-21)

| Binding | Span | Done signal | Needs t-1992? |
|---------|------|-------------|---------------|
| `/brana:build` TDD loop | red → green (refactor OUTSIDE span) | all `AC:` exit codes == 0 | No |
| `/brana:fix` | reproduce → fix → verify | failing test now passes | No |
| `/brana:reconcile` | detect → fix → re-validate | validate.sh exit 0 | No |
| per-skill-phase (generalized) | any gate-free phase | phase's machine-verifiable `done` | **Yes (Stage 4 only)** |

## Sequencing (revised after stress test — t-1992 is NOT a hard blocker)

The three specific bindings have self-contained, already-external done-signals → they need
nothing from t-1992. t-1992 gates ONLY the generalized binding (Stage 4).

```
Stage 1  t-2194 ADR — generalized design + 3 specific bindings   ← needs nothing from t-1992
Stage 2  BUILD build's TDD binding (stops AT the TDD gate)        ← soak, collect evidence
Stage 3  build fix + reconcile bindings                          ← after build has a track record
   ───── t-1992 step-state contract lands in parallel, off critical path ─────
Stage 4  generalized "any gate-free phase declares a /goal"      ← NOW needs t-1992
```

## Security invariants (the design's spine — from Attack-3 stress test)

`/goal` is an optimizer with the done-signal as objective function → it will Goodhart a weak
predicate. "External done-predicate" is necessary but NOT sufficient. Three hard invariants:

| Invariant | Defends against | Mirrors |
|-----------|-----------------|---------|
| 1 — **presence interlock**: auto-advance requires a structurally-verified interactive session | headless auto-complete / silent gate-bypass | §2b binding A/B split |
| 2 — **done-signal immutability**: loop may not modify the assertions it's graded by; `*.test.*`/AC change mid-iteration trips a gate (or grade vs pinned copy) | AC-gaming, assertion-weakening | t-2193 C3, t-2173 |
| 3 — **bounded span**: iterate-until = red→green only; refactor is capped/optional, outside the predicate | LoopTrap P7 (refactor-forever) | ADR-050 §t-517 caps |

## Risks (pre-mortem)

- **t-1992 derivation may not hold** — if `next_step`/`gate_pending` aren't cleanly derivable
  from a step registry, t-1992 balloons. Mitigated: gates only Stage 4, off the critical path.
- **Premature abstraction** — generalized contract designed before evidence. Mitigated:
  Stages 2–3 produce real bindings first; generalize (Stage 4) after.
- **Gate complacency** — `/goal` turns human gates into rubber-stamps. Mitigated by Invariant 1
  + keeping spans short (few gates per session).

## Resolved (was open)

- ~~t-1992 a HARD blocker?~~ → No. Gates Stage 4 only; specific bindings are independent.
- ~~bottom-up vs top-down?~~ → Synthesis: generalized DESIGN now (Stage 1), specific bindings
  BUILT first (Stages 2–3) against their own done-signals, generalization BUILT last (Stage 4).

## Outcome (2026-06-21)

Shaped into **ADR-061** (proposed). Challenger PROCEED-WITH-CHANGES (1 BLOCKER, 2 HIGH,
2 MEDIUM) — all incorporated. Build tasks decomposed under t-2194:
- t-2204 — harden goal-completion.sh (invariant 2 + presence interlock) — BLOCKER precondition
- t-2205 — Stage 2: build TDD binding (blocked_by t-2204)
- t-2206 — Stage 3: fix + reconcile bindings (blocked_by t-2205)
- t-2207 — Stage 4: generalized binding (blocked_by t-2206 + t-1992)

## Relations

- t-1992 — step-state contract (the `done` predicate source)
- ADR-050 — auto-advance caps (≤3, machine-verifiable, never cross gate)
- pattern_looptrap-autonomy-findings — P5/P7 self-assessed-done is the danger
