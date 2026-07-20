# ADR-065: Epic as the Single-Tree Top Node (reversing v2 initiative-as-top)

- **Status:** Proposed
- **Date:** 2026-07-20
- **Evidence:** [backlog-v3-schema.md](../features/backlog-v3-schema.md) D1; live task-shape inspection (2,156 tasks); [brana-backlog-v2-schema.md](../../ideas/brana-backlog-v2-schema.md)
- **Related:** ADR-002 (tasks-as-data-layer), ADR-047 (AC schema), [brana-v3 redesign](../../ideas/brana-v3-redesign.md)

## Context

The backlog carries **two competing grouping systems** in its schema:

1. A **type/level tree** — `level` *and* `type` (redundantly) encode `initiative → milestone → phase → task → subtask`, linked by `parent`. `initiative` is the top.
2. A **flat `epic` string field** — 43 values (`dx-tooling`, `harness-v2`, …), orthogonal to that tree, with no status/lifecycle/structure.

A task therefore has two independent answers to "what is this part of": its position in the type tree *and* its `epic` string. This duplication is a direct cause of the operator's felt "I get lost in epics" — and of epic sprawl (43 epics, ~19 already done but never closed, no WIP cap, no close).

**Why v2 put `initiative` on top ([brana-backlog-v2-schema.md](../../ideas/brana-backlog-v2-schema.md) §1):** to map 1:1 to **Linear's hierarchy — Initiative → Project → ProjectMilestone → Issue** — and to make initiatives queryable/hierarchically-visible instead of encoded as tags. This is the load-bearing reason the reversal must address; it is not arbitrary.

**The operator's model** (this conversation, 2026-07-20): an **epic = "what we're building," and empty = feature done.** It is the home base they navigate by — the level they want to see one of at a time, WIP-capped, closable. Semantically this is *a deliverable that completes* — which maps to a Linear **Project**, not a Linear Initiative.

## Decision

1. **Collapse `level` and `type` into one hierarchy field** (survivor chosen in D8 of the schema spec — `type` is more populated). One tree, not two fields for one tree.

2. **Promote `epic` to the top *working* node of that single tree**, absorbing the flat `epic` string field. Epic gains node semantics: `status` (`active`/`next`/`parked`/`done`/`archived`), `wip_limit`, gate (`blocked_by`), contract, auto-close-on-empty. The flat string field retires.

3. **`initiative` is retained as an *optional* super-node above epic**, not the default top. It exists only when several epics roll up into one strategic theme; most work never uses it. This preserves the Linear mapping:

   | Backlog node | Linear | Required? |
   |---|---|---|
   | `initiative` (optional super-node) | Initiative | no — only for multi-epic themes |
   | **`epic`** (the home base, empty = done) | **Project** | the default top |
   | `milestone` / `phase` / `layer` / `component` | ProjectMilestone | optional depth |
   | `task` | Issue | yes |
   | `subtask` | Sub-issue | optional |

This **reverses "initiative-as-the-default-top"** (v2) in favor of **"epic-as-the-default-top, initiative-as-optional-above."** It is a deliberate supersession of the v2 decision, taken with the Linear constraint in view — not an oversight.

## Consequences

- **Linear sync (`sync_linear.rs`)** remaps: `epic → Project` (was: `initiative → Initiative` as the primary unit). The 3-pass sync logic adjusts; initiative sync becomes conditional on the optional super-node existing.
- **The ~10 surviving epics** (post-cleanup) become epic nodes; their tasks re-parent to them; the flat field is dropped.
- **`level`/`type` collapse** touches ~2,100 tasks (mechanical backfill + drop one field).
- **Navigation simplifies**: default depth is `epic → task`; the operator sees one active epic, WIP-capped.
- **Reversibility**: the reversal is data-level (field values + parent links), scriptable and auditable; no history lost.

## Alternatives considered

- **Keep initiative-as-top (status quo v2).** Rejected: leaves the two-grouping-systems duplication (flat `epic` tag *and* the tree) unresolved — the root cause of the sprawl.
- **Epic *replaces* initiative entirely (no super-node).** Rejected *if* Linear parity is wanted — it drops the Initiative tier and forces `epic → Linear Initiative`, breaking the natural `epic = Project` (completion) semantics. Adopt this variant only if Linear sync is abandoned (see open question).

## Open question (blocks Accepted status)

**Does Linear parity still matter?** If Linear sync is live/planned, keep the optional `initiative` super-node (this ADR as written). If Linear sync is abandoned, take the simpler variant: kill `initiative` outright, epic is the sole top. The operator must confirm which — it flips consequence #1 and alternative #2.
