---
status: proposed
---
# ADR-062: Step-State Contract — Derive {next_step, gate_pending} from a Static Step Registry + the Run-State Log

**Status:** Proposed (2026-06-21; one challenger pass, all findings incorporated)
**Date:** 2026-06-21
**Deciders:** Martín Rios
**Tags:** loop-native, factory, substrate, step-state, autonomy, checkpoint
**Tasks:** t-1992 (this ADR) · gates t-1994 (foreman recipe) and ADR-061 Stage 4 (generalized `/goal` binding)
**Extends:** [checkpoint-resume.md](../features/checkpoint-resume.md) (the shipped `~/.claude/run-state/{task_id}.jsonl` step log) · build STEP REGISTRY (`system/skills/build/phases/load.md` Step 0b) · `system/skills/_shared/guided-execution.md`
**Relates:** [ADR-050 §t-517](ADR-050-loop-request-protocol.md) (settled advancement policy — this ADR supplies the data that policy reads; it does NOT re-decide it) · [ADR-061 §3](ADR-061-goal-integration-three-primitive.md) (this contract is load-bearing for ADR-061's generalized binding) · [loop-native redesign](../../research/2026-06-11-loop-native-redesign.md) (roadmap step 4) · field-note_two-file-model-do-not-clear

---

## Context

The loop-native redesign's roadmap step 4 calls for every pipeline step to end by writing
`{checkpoint, next_step, gate_pending}`, so loops can **pause at gates instead of forcing
them** — "the real architectural change." The research doc left one open question: does
step-state live in `session-state.json` or a new run-state file?

Three of the four words are already settled by shipped work; only the contract that joins
them is new:

- **`checkpoint`** is SHIPPED. [checkpoint-resume.md](../features/checkpoint-resume.md)
  (t-1108, 2026-04-10) writes one JSONL line per completed step to
  `~/.claude/run-state/{task_id}.jsonl`, with a RESUME CHECK at skill entry, CLOSE cleanup,
  and an M+/has-task_id gate. This ADR does **not** invent a new checkpoint mechanism.
- **Advancement policy** is SETTLED. [ADR-050 §t-517](ADR-050-loop-request-protocol.md)
  fixes *when* an auto-advance may fire (machine-verifiable checkpoint written; never cross
  a human gate; ≤3 consecutive auto-advances; `validate.sh` passed at the last gate). This
  ADR is OUT OF SCOPE to redesign it — it supplies the two **inputs** §t-517 already
  references ("the next step is **not** a gate step") but never had a machine-readable
  source for.

The gap: today a partial "step registry" exists, but only as (a) prose lists of step names
hardcoded in `load.md` Step 0b, and (b) ephemeral **CC Tasks** created per-session
(`_shared/guided-execution.md`) that die with the session. Neither is machine-readable,
neither carries gate flags, and neither is joined to the durable run-state log. So
`next_step` and `gate_pending` cannot be computed by a foreman/loop today — they live only
in the model's head.

## Decision

**Do NOT store `next_step` or `gate_pending` as runtime state. Derive both** by joining a
new *static* per-procedure **step registry** (step order + a gate flag per step — pure
metadata, versioned in the repo) against the *already-shipped* run-state completed-steps
log. The only new per-run write stays the existing checkpoint line, optionally enriched
with the gate flag for self-containment.

### 1. The step registry — static, repo-versioned, one per procedure×strategy

A machine-readable JSON file co-located with the procedure it describes (so the gate author
and the registry are reviewed together). One registry per strategy variant, because build's
step sequence is strategy-dependent (Feature vs Bug fix vs Spike).

```jsonc
// system/skills/build/registries/feature.json
{
  "procedure": "build",
  "strategy": "feature",
  "version": 1,
  "steps": [
    { "id": "LOAD",      "gate": false },
    { "id": "CLASSIFY",  "gate": true,  "contains_internal_gates": false },  // APPROVE AskUserQuestion
    { "id": "SPECIFY",   "gate": true },                                     // SPECIFY→DECOMPOSE artifact gate
    { "id": "DECOMPOSE", "gate": false },
    { "id": "BUILD",     "gate": true,  "contains_internal_gates": true },   // N per-subtask TDD gates inside
    { "id": "EXTRACT",   "gate": false },
    { "id": "EVALUATE",  "gate": false },
    { "id": "PERSIST",   "gate": false },
    { "id": "CLOSE",     "gate": true }                                      // state-commit gate
  ]
}
```

`gate: true` ⇔ the step requires a human touchpoint per ADR-050 §t-517 #2 (CLASSIFY,
APPROVE, any AskUserQuestion gate, all SKIP-with-reason gates, the artifact gate, the
per-subtask TDD gate, state-commit). The registry is the **single machine-readable home**
for the gate list ADR-050 §t-517 #2 already enumerates in prose. Step `id` values are
exactly the names already written by checkpoints and listed in `load.md` Step 0b — no new
vocabulary.

**Steps with internal gates (challenger Finding 1 — resolves the BUILD granularity BLOCKER).**
The run-state log records one line per *major* step, but BUILD fires the per-subtask TDD
gate **N times inside the BUILD loop** (one per subtask from DECOMPOSE). A single boolean
`gate` on the BUILD row therefore cannot locate "BUILD started, subtask 3 of 7 at its TDD
gate." Rather than make the registry dynamic (subtask granularity is unknown until DECOMPOSE
and would multiply registries), this ADR **coarsens**: a step carrying
`contains_internal_gates: true` is **always** `gate: true`, and **the foreman/loop is
prohibited from auto-advancing *into* or *through* it.** Sub-step sequencing inside such a
step (BUILD's per-subtask red→green) is owned by the interactive session or the `Workflow`
crew, NOT derived from this contract. The foreman parks at BUILD *entry*; what happens
inside BUILD is the supervised tier's job (ADR-061 Stage 2's `/goal` build binding operates
there interactively). This keeps the registry coarse (~9 rows per strategy) and the
derivation total.

### 2. The run-state log — UNCHANGED, optionally enriched

Stays at `~/.claude/run-state/{task_id}.jsonl`, one line per completed step
(checkpoint-resume.md format). The only additive change: each line MAY carry the step's
gate flag so a reader can compute state from the log alone when the registry is unavailable
(defensive; the registry is authoritative).

```json
{"step":"LOAD","completed":"2026-06-21T14:30:00Z","task_id":"t-1992","gate":false}
{"step":"CLASSIFY","completed":"2026-06-21T14:32:00Z","task_id":"t-1992","gate":true}
```

### 3. Derivation rules (the contract)

Given registry `R` (ordered `steps`) and the run-state log `L` for a task:

- `completed := { line.step for line in L }`
- **`next_step` := first `s` in `R.steps` where `s.id ∉ completed`** (null ⇒ procedure done).
- **`gate_pending` := (next_step ≠ null) AND `R.steps[next_step].gate == true`.**
- A step with `contains_internal_gates: true` is never auto-advanced *through*: even once
  its checkpoint line is written, the foreman treats re-entry/continuation inside it as a
  parked, human/crew-owned region.

A loop/foreman consuming this: if `gate_pending` → **park and hand back to the human** (never
auto-advance — ADR-050 §t-517 #2). If not `gate_pending` AND §t-517's other three conditions
hold (checkpoint written, ≤3 auto-advances, validate passed) → auto-advance into `next_step`.
The derivation produces the *inputs*; §t-517 remains the *decision*.

### 4. Storage decision (AC) — derive, don't store; durable side in run-state, NOT session-state

| Candidate | Verdict | Rationale |
|-----------|---------|-----------|
| Runtime fields `next_step`/`gate_pending` | **Rejected** | Derivable (§3). Stored copies are a second source of truth that desyncs the instant a step completes without rewriting them. |
| `session-state.json` | **Rejected** (durable side) | Step progress must survive session death (the foreman dispatches across sessions; ADR-050's foreman is per-session). Per field-note_two-file-model-do-not-clear, session-state carries transient session-scoped focus; mixing cross-session step progress in invites the clear-on-close hazard. |
| `~/.claude/run-state/{task_id}.jsonl` (extend) | **Accepted** | Precedent (checkpoint-resume.md), already cross-session-durable, task-keyed, outside the repo (no git noise), cleaned at CLOSE. We extend it; we do NOT invent a third state location. |
| Step **registry** in repo | **Accepted** (static only) | Order+gate metadata is procedure *structure*, not runtime state — it belongs in version control next to the procedure, reviewed when the procedure changes. |

**Two-file read protocol (challenger Finding 6).** The foreman reconstructs state from
exactly two files: `{task_id}.jsonl` for step position (this ADR's durable side) and
`active-goal.json` for goal criteria + `base_ref` (written at `/goal` start). No additional
state file is needed; this two-file read is the complete state surface. Net: the only
per-run write stays the checkpoint line; `next_step`/`gate_pending` are computed on read.

### Relation to ADR-050 §t-517 (required by AC)

§t-517 is **settled advancement POLICY** and is NOT re-litigated here. This ADR is the
**data layer §t-517 reads**: condition #2 ("next step is not a gate step") had no
machine-readable source — `gate_pending` (§3) is that source; condition #1 ("the completed
step wrote its run-state checkpoint") is exactly the log we derive `completed` from. This
ADR makes §t-517 mechanically checkable instead of model-judged.

### Relation to ADR-061 (required by AC)

ADR-061 §3 states t-1992 is load-bearing **for the generalized `/goal` binding (Stage 4)**
— the three specific bindings carry self-contained external done-signals. This ADR is
therefore **off ADR-061's Stage 1–3 critical path** and supplies the `next_step`/`gate_pending`
predicate the generalized binding consumes.

**Conditional dependency (challenger Finding 3).** ADR-061's Open item asks Stage 2 to decide
whether the build `/goal` binding's per-subtask TDD gate sits at the span *boundary* or
*inside* it. If Stage 2 places it at the boundary, this ADR stays off the Stage 1–3 critical
path. If Stage 2 places it *inside* the span, t-1992 becomes a Stage 2 dependency (the
binding needs the registry to locate the boundary) and ADR-061's sequencing diagram must be
updated.

## Consequences

**Positive**
- One write per step (unchanged); state is a pure function of `(registry, log)` — no desync
  class of bug, no third state location.
- ADR-050 §t-517's gate condition becomes machine-checkable; the foreman (t-1994) and the
  generalized `/goal` binding (ADR-061 Stage 4) can compute "pause at gate" deterministically.
- The gate list moves from prose-in-three-places (ADR-050, load.md, guided-execution) to one
  versioned, reviewed artifact.

**Negative / risks**
- **Registry↔procedure drift (challenger Findings 2+4 — the validate check is the real
  mitigation, and it does not exist yet).** A step renamed/reordered/gate-changed in the skill
  but not in the registry breaks derivation. The **primary** mitigation is a *new, required*
  `validate.sh` check (a build task, not inherited): bidirectional — every checkpoint-emitting
  step `id` must exist in its registry and vice-versa, and a step's `gate`/`contains_internal_gates`
  must match its phase file. The check is **blocking** (fail ⇒ ERRORS++). Co-location is only a
  *secondary, advisory* aid. **The gate-as-static-snapshot process rule (a step that gains a
  gate later must flip the flag in the same commit) is NOT relied upon until that validate
  check is green in CI** — enforcement before dependence.
- **Strategy multiplication** — one registry per strategy variant. Acceptable (short, already
  enumerated in load.md Step 0b); generate from that single prose source if duplication bites.
- **AC-gaming via log edits (challenger Finding 5 — connects to the just-merged
  goal-completion.sh hardening).** When the foreman derives `gate_pending` from the append-only
  run-state log, that log becomes a path the grader reads — i.e. a grader path under ADR-061
  invariant 2. A `/goal` loop could append a fabricated completed-step line to make a gated
  step derive as `gate_pending=false`. Therefore: **before the Stage 4 generalized binding is
  trusted, `goal-completion.sh`'s `GRADER_RE` (currently
  `(\.test\.|(^|/)tests/|(^|/)__mocks__/|(^|/)\.claude/tasks\.json$)`) MUST be extended to
  include `run-state/` paths.** This is a required Stage 4 deliverable, not a future
  consideration.

## Alternatives considered

- **Store `next_step`/`gate_pending` as runtime state** (the literal roadmap-step-4 phrasing
  "every step *writes* {checkpoint, next_step, gate_pending}") — **Rejected.** Both are
  derivable from data we already have. Storing them adds a second source of truth that desyncs
  on every step completion. The roadmap phrasing is satisfied in effect: the checkpoint is
  written; the other two are *available* per step, just computed not stored.
- **Make the registry dynamic at subtask granularity** (one row per DECOMPOSE'd subtask) —
  **Rejected** (challenger Finding 1): subtask count is unknown until DECOMPOSE and would
  multiply registries 7×N. Coarsening via `contains_internal_gates` (§1) keeps derivation
  total without it.
- **Put step progress in `session-state.json`** — Rejected (§4): not cross-session-durable for
  the foreman; risks the transient-clear hazard.
- **Keep the CC-Tasks step registry as the source** (guided-execution.md today) — Rejected: CC
  Tasks die with the session and carry no gate flag; they remain useful as the *in-session*
  compression-resilience view but are not the cross-session contract.
- **A third dedicated `step-state.json` per task** — Rejected: violates "don't invent a third
  state location"; the run-state log already is the durable per-task store.

## Open (deferred to build)

- Registry hand-authored per strategy vs **generated** from load.md Step 0b's prose (single
  source, removes duplication risk, adds a build step).
- `run-state` line gate-flag enrichment: MAY (registry authoritative) vs MUST (log
  self-describing). Chosen MAY; reversible.
- Exact shape of the bidirectional validate check (parsing `☑ Checkpoint — STEP` blockquotes
  in `phases/*.md` against the registry JSON).

## Challenger dispositions (2026-06-21, t-1992 AC)

PROCEED WITH CHANGES — 1 BLOCKER, 2 HIGH, 2 MEDIUM, 1 LOW, all incorporated:

| # | Attack | Severity | Disposition |
|---|--------|----------|-------------|
| 1 | BUILD per-subtask TDD gate breaks step-level derivability (1 registry row, N internal gates) | BLOCKER | **Fixed** — `contains_internal_gates` coarsening; foreman never auto-advances into/through such a step (§1, §3) |
| 2 | Registry↔procedure drift: validate check doesn't exist; co-location overclaimed | HIGH | **Fixed** — validate check named primary + required + bidirectional + blocking; co-location demoted to advisory (Risks) |
| 3 | ADR-061 §3 "off critical path" understates a conditional Stage-2 dependency | MEDIUM | **Fixed** — conditional-dependency clause added (Relation to ADR-061) |
| 4 | Gate-snapshot process rule has no enforcement | HIGH | **Fixed** — rule not relied upon until the validate check is green in CI (Risks) |
| 5 | Deriving `gate_pending` from the log opens an AC-gaming surface; run-state not in `GRADER_RE` | MEDIUM | **Fixed** — run-state declared a grader path; `GRADER_RE` extension is a required Stage 4 deliverable (Risks) |
| 6 | Foreman read path underspecified (jsonl + active-goal.json) | LOW | **Fixed** — two-file read protocol named (§4) |
