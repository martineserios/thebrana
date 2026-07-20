# ADR-065: Epic as the Sole Hierarchy Top Node (reversing v2 initiative-as-top)

- **Status:** Accepted
- **Date:** 2026-07-20
- **Evidence:** [backlog-v3-schema.md](../features/backlog-v3-schema.md) D1; live task-shape inspection (2,156 tasks); [brana-backlog-v2-schema.md](../../ideas/brana-backlog-v2-schema.md); operator decision 2026-07-20
- **Related:** ADR-002 (tasks-as-data-layer), ADR-047 (AC schema), [brana-v3 redesign](../../ideas/brana-v3-redesign.md)

## Context

The backlog carries **two competing grouping systems** in its schema:

1. A **type/level tree** — `level` *and* `type` (redundantly) encode `initiative → milestone → phase → task → subtask`, linked by `parent`. `initiative` is the top.
2. A **flat `epic` string field** — 43 values (`dx-tooling`, `harness-v2`, …), orthogonal to that tree, with no status/lifecycle/structure.

A task therefore has two independent answers to "what is this part of." This duplication is a direct cause of the operator's felt "I get lost in epics" — and of epic sprawl (43 epics, ~19 already done but never closed, no WIP cap).

**Why v2 put `initiative` on top ([brana-backlog-v2-schema.md](../../ideas/brana-backlog-v2-schema.md) §1):** to map 1:1 to **Linear's hierarchy — Initiative → Project → ProjectMilestone → Issue** — and, explicitly, because "initiatives are currently encoded as **tags**, which works but **isn't queryable**." That queryability gap is the stated reason for promoting initiative to a node.

**The operator's model** (2026-07-20): an **epic = "what we're building," empty = feature done** — the home base they navigate by, WIP-capped and closable. Semantically a *deliverable that completes* = a Linear **Project**. And on Linear itself: *"keep a way to sync with Linear — we'll eventually adopt it; keep the link possible."*

## Decision

1. **Collapse `level` and `type` into one hierarchy field** (`type` survives — more populated, 1,825 vs 1,254). One tree, one field.

2. **Promote `epic` to the sole top node** of that single tree, absorbing the flat `epic` string field. Epic gains node semantics: `status` (`active`/`next`/`parked`/`done`/`archived`), `wip_limit`, gate (`blocked_by`), contract, auto-close-on-empty. The flat string field retires.

3. **Remove the `initiative` node level entirely.** v2's reason for it — "tags aren't queryable" — is **dissolved by v3's key:value tags** (schema D8): a Linear-Initiative grouping, if ever adopted, is a first-class *queryable* `initiative:<slug>` tag, no node level required. The default tree is `epic → task`; depth is opt-in.

4. **Keep the Linear link possible** without carrying an initiative tier in daily use:

   | Backlog | Linear | Mechanism |
   |---|---|---|
   | **`epic`** (sole top, empty = done) | **Project** | node → Project |
   | `initiative:<slug>` **tag** (optional) | Initiative | queryable tag → Initiative grouping, only if/when Linear is adopted |
   | `milestone` / `phase` (optional depth) | ProjectMilestone | node |
   | `task` | Issue | node |
   | `subtask` | Sub-issue | node |

This **reverses v2's initiative-as-top** in favor of **epic-as-sole-top**, while *preserving Linear sync as a future option* through the tag mechanism — resolving the apparent tension between "kill initiative" (simpler tree) and "keep the Linear link" (they operate on different objects: node vs mapping).

## Consequences

- **Linear sync (`sync_linear.rs`)**, when adopted, maps `epic → Project`; the Initiative pass becomes conditional on `initiative:` tags existing. Sync stays possible; nothing about killing the node forecloses it. Expect a refactor/rethink when Linear is actually turned on (operator: "we can refactor or rethink it").
- **The ~10 surviving epics** (post-cleanup) become epic nodes; tasks re-parent via `parent`; the flat field drops.
- **`level`/`type` collapse** touches ~2,100 tasks (mechanical backfill, drop `level`).
- **Navigation simplifies**: default depth `epic → task`; one active epic, WIP-capped.
- **Reversibility**: data-level (field values + parent links + tags), scriptable and auditable; no history lost. Re-introducing an initiative node later is itself a scriptable promotion of the `initiative:` tag.

## Alternatives considered

- **Keep initiative-as-top (status quo v2).** Rejected: leaves the two-grouping-systems duplication unresolved — the root cause of the sprawl.
- **Retain `initiative` as an optional super-node.** Rejected: unnecessary once key:value tags make Initiative-grouping queryable; adds a level the operator explicitly wants gone.
- **Abandon Linear parity entirely.** Rejected: operator wants the link kept possible — preserved here via the `initiative:` tag → Linear Initiative mapping.
