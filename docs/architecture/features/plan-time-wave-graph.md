---
status: shipped
---
# Plan-time wave graph (t-2843)

> Implements [ADR-080](../decisions/ADR-080-plan-time-wave-graphs-epic-runner.md) §2.
> See [wave-gate-enforcement.md](wave-gate-enforcement.md) for the underlying
> `parent:` selector, gate check, and drain mechanics this feature emits waves
> against.

Status: **implemented (t-2843, 2026-08-14).**

## Goal

Before this feature, every wave was born by hand: tag tasks, create the wave,
chain gates, approve tasks one at a time. ADR-080 §2's brief: waves should be
**born at planning time**, from the plan's own structure, so the human never
hand-rolls a wave graph for the common case (one wave per milestone).

## Design decisions

- **One wave per milestone, `parent:<ms-id>` selector.** No tags written — the
  plan's own hierarchy *is* the wave graph (ADR-065 D3: waves select, they
  don't own).
- **Gate chain derived, not asked for.** If any task under milestone B is
  `blocked_by` a task under milestone A, wave-B gets `gate: wave-A`. This reuses
  dependency information the planner already collected (plan.md step 7 /
  decompose-mode.md's `Blocked by` column) rather than asking a second time.
- **Shared emission primitives, not two implementations.** `wave_name_for_milestone`
  and `wave_gate_chain_has_cycle` live in one place —
  [`system/skills/_shared/wave-graph-emit.md`](../../../system/skills/_shared/wave-graph-emit.md)
  — sourced by both call sites. `resolve_branch_prefix`'s two independently
  hand-rolled mappings drifted and mislabelled three defect branches before
  anyone noticed (t-2494); a wave-naming or cycle-check drift between plan.md
  and decompose-mode.md would fail the same way, silently.
- **Cycle detection is a bounded chain-walk, not general DFS.** A wave's `gate`
  is a single id or null, so the gate chain is a functional graph (out-degree
  ≤ 1). Walking a chain past the total wave count proves a cycle by pigeonhole
  — equivalent to DFS-with-visited-set for this restricted shape, without bash
  needing to track one.
- **Two lines of defense, not one.** The plan-time check here is the first line;
  the epic runner's PREFLIGHT cycle-STOP (ADR-080 §3.1) is the last, not the
  only one — a cyclic graph must never reach WRITE in the first place.
- **Write only on approval.** The graph is computed and displayed during
  PROPOSE/Draft-tree, but `brana backlog wave add` only runs after the human
  approves — same gesture as the task tree, no separate confirmation.

## Code flow

- `system/skills/backlog/phases/plan.md` — new step **7a WAVES**, between step 7
  (dependencies) and step 8 (PROPOSE); step 8 now displays the graph alongside
  the tree; step 14 (WRITE) creates the wave objects on approval.
- `system/skills/build/phases/decompose-mode.md` — new step **3a WAVES**, between
  step 3 (Draft tree) and step 4 (approval), gated on the tree root resolving to
  an epic ancestor (`resolve_epic_ancestor`, [epic-ancestor-walk.md](../../../system/skills/_shared/epic-ancestor-walk.md));
  step 5 (Persist) creates the wave objects using the real `ms-N` ids just
  assigned.
- `system/skills/_shared/wave-graph-emit.md` — `wave_name_for_milestone` and
  `wave_gate_chain_has_cycle`, the shared primitives both steps above call.

## Testing

`tests/procedures/test-wave-graph-emit.sh` — extracts the `WAVE-GRAPH-EMIT-BLOCK`
by named marker (not position, t-2493) and asserts: wave naming, acyclic chains
(linear, ungated, shared-gate fan-in) pass, cyclic chains (2-cycle, 3-cycle,
self-gate) fail with a diagnostic, the literal `"null"` gate value is treated as
ungated, and both call sites reference the shared file rather than restating the
check. Run: `bash tests/procedures/test-wave-graph-emit.sh`.

## Known limitations

- **Milestone with multiple upstream dependencies collapses to one gate** — a
  wave gates on at most one other wave. The tie-break (most cross-milestone
  `blocked_by` edges) is surfaced in the PROPOSE/Draft-tree display so the human
  can override it, but there is no multi-gate representation.
- **DDD glossary entries deferred.** ADR-080's Consequences section assigns
  `MODEL-001` updates (Wave graph, Epic runner, Lease, etc.) to t-2846, sequenced
  after the machinery it describes actually ships — not duplicated here.
