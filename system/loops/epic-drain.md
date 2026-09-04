---
name: epic-drain
pacing:
  active_delay: "90s"
  waiting_delay: "20m"
  empty_delay: "30m"
autonomy: L1
supervised: true
drains: ["an epic's parent-chain wave graph (topo-sorted by gate)"]
fills: []
spawns: []
records: "single-sourced in docs/architecture/features/loops-library.md §Beat record schema"
---
# epic-drain (catalog entry)

Catalog pointer only — the committed beat procedure and full runner contract
live at
[docs/guide/workflows/epic-drain.md](../../docs/guide/workflows/epic-drain.md)
(t-2845, ADR-080). Read that file to run this loop; nothing here is
authoritative. This entry exists so `system/loops/` is a complete index of
every committed loop, without forking `epic-drain.md`'s procedure content —
same treatment as [drain-loop.md](drain-loop.md), the loop it generalizes
(loops-library contract, §Boundaries).

## Fan-out per beat (ADR-090)

Each beat pulls up to `N` tasks from the active wave — `N` sequential atomic
pulls, then **one build-loop instance per pulled task, each in its own
worktree, dispatched via native Agent/Task fan-out and run in parallel within
the beat** (ADR-090 §1/§2). `N` is an operator-set fan-out cap fixed at launch,
not a wave field; the beat reports every id it pulled. Width, sequencing, and
reporting are single-sourced in
[docs/guide/workflows/epic-drain.md](../../docs/guide/workflows/epic-drain.md)
§The loop prompt step 4 — not restated here.

## Denied verbs

Single-sourced in [docs/guide/workflows/epic-drain.md](../../docs/guide/workflows/epic-drain.md)
§Denied verbs — not restated here.

**Proven:** fixture-epic rehearsal + 2 real production beats against the live
`backlog-drain` epic's `wave-4`, 2026-08-14 (t-2845). See the source doc's own
Proof-of-life section.
