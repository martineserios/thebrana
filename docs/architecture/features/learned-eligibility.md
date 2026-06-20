# Feature Spec — Learned Eligibility for the Autonomous Runner (Stage 4)

**Task:** t-2142 · **Status:** DESIGN ONLY (no implementation; gated on soak) · **Date:** 2026-06-20
**Basis:** [autonomous-runner](autonomous-runner.md) · [ADR-059](../decisions/ADR-059-multi-agent-substrate-selection.md) · [ADR-060](../decisions/ADR-060-branch-strategy-autonomous-agents.md) · ADR-050 (autonomy caps)

## Problem

The runner's eligibility is **default-deny + manual whitelist** (`execution: autonomous`). That is correct for earning trust but does not *scale*: every newly-safe task shape must be hand-marked. Stage 4 graduates task **shapes** to auto-eligible from the runner's own **track record** — so the set of work the runner can safely take grows from evidence, not hand-labeling.

**Hard precondition:** this requires a track record. It cannot be built until Stages 1-3 have run live for a meaningful period (the ledger is the dataset). Implementing it before the soak would be learning from noise. **Do not build until the runner has produced ≥ N live outcomes** (proposed N ≥ 50 ran/parked/failed across ≥ 2 weeks).

## The dataset (already being produced)

The runner's JSONL **ledger** (`~/.claude/scheduler/runner-ledger-*.jsonl`) records one row per task with `{id, subject, decision, reason, ts}`. Augment each `ran` row at human-review time with the **outcome** (merged-clean / merged-with-edits / rejected). That `(task-shape → outcome)` history is the training signal. No new store — extend the ledger.

## Task "shape" features (not the task, the shape)

Eligibility learns over *shapes*, never specific tasks:
- `kind` (docs/fix/refactor/ops/…), `effort` (XS/S/M), `tags`, `priority`
- file-surface signals (touches `docs/` only? tests only? `system/` behavioral?)
- presence of `AC:` lines, description length/specificity
- the plan-gate verdict distribution for that shape (how often `would-park`)

## Decision model (deliberately simple)

A shape graduates to auto-eligible when its track record clears a **conservative threshold**:
> ≥ K live runs of that shape AND ≥ 95% merged-clean AND 0 rejected-as-harmful AND not P0.

Start with a **transparent rule/table**, not an opaque model — autonomy decisions must be auditable (why was this auto-eligible?). A learned classifier is a later option only if the rule table proves insufficient; if used, it must emit the features that drove the decision. (Avoid the ruflo `neural_train` trap — ADR-059: it doesn't actually train.)

## Safety invariants (unchanged from ADR-050/060)

Learning **widens reach, never loosens guards.** Auto-eligible shapes still: branch+worktree-isolate, verify, human-gated merge, never P0, consecutive-fail kill, secret-gate. A graduated shape that starts failing is **auto-demoted** (the threshold is continuous, not a one-way ratchet).

## Open questions

1. Per-shape K and the demotion window (needs real outcome variance to calibrate).
2. Where the human records the review outcome (a `brana runner outcome <id> <verdict>` command vs parsing PR merge state).
3. Rule-table vs learned-classifier — decide after the soak shows whether the table generalizes.

## Out of scope

Implementation. This spec exists so the substrate's end-state is fully designed (the capstone, [substrate-end-state](../substrate-end-state.md)); Stage 4 is built only after the Stage 1-3 soak produces the dataset.
