# Plan-time wave graph

`/brana:backlog plan` and epic-scoped `/brana:build decompose` now propose a
**wave graph** alongside the task tree — one wave per milestone, ready to drain,
with no extra tagging step.

## Quick Start

Plan a phase with 2+ milestones as usual:

```
/brana:backlog plan "adr080-consumers" --parent t-2811
```

When you reach the proposal step, you'll now see the wave graph shown alongside
the task tree:

```
## Wave Graph
- backlog-drain-adr080-core: parent:ms-1, gate: none, contract: "..."
- backlog-drain-adr080-consumers: parent:ms-2, gate: backlog-drain-adr080-core, contract: "..."
```

Approve the plan as normal — the waves are created (`status: queued`) in the
same write as the task tree. From there, drain them exactly like a hand-rolled
wave: `brana backlog wave drain <name>`, then arm the loop per
[drain-loop.md](../workflows/drain-loop.md).

## How It Works

- **One wave per milestone.** No tags to write — the wave's selector is
  `parent:<milestone-id>`, so every task under that milestone matches.
- **Gates are inferred, not asked for.** If a task under a later milestone is
  blocked by a task under an earlier one, the later milestone's wave gates on
  the earlier one's wave automatically.
- **Nothing writes until you approve.** The graph is computed and shown during
  the same proposal step as the task tree; declining or adjusting the plan
  discards it along with the tree.
- **A cyclic dependency structure is refused, not silently written.** If your
  milestone dependencies form a cycle, planning stops with a diagnostic instead
  of producing a wave graph the drain loop could never resolve.

## Examples

**Fewer than 2 milestones** — the WAVES step is skipped silently; you get a
plain task tree, same as before this feature existed.

**Two independent milestones** (no cross-milestone `blocked_by` edges) — both
waves are created with `gate: none`; either can drain first.

**A dependency chain across three milestones** — three waves are created, each
gated on the one before it, so draining proceeds in the order the plan already
implied.
