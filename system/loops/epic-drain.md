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

## Denied verbs

Single-sourced in [docs/guide/workflows/epic-drain.md](../../docs/guide/workflows/epic-drain.md)
§Denied verbs — not restated here.

**Proven:** fixture-epic rehearsal + 2 real production beats against the live
`backlog-drain` epic's `wave-4`, 2026-08-14 (t-2845). See the source doc's own
Proof-of-life section.
