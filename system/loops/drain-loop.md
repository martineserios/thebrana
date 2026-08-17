---
name: drain-loop
pacing:
  active_delay: "90s"
  waiting_delay: "20m"
  empty_delay: "30m"
autonomy: L1
supervised: true
drains: ["tasks.json waves (selector + ac_state gate + wip_limit)"]
fills: []
spawns: []
records: "single-sourced in docs/architecture/features/loops-library.md §Beat record schema"
---
# drain-loop (catalog entry)

Catalog pointer only — the committed beat procedure and full runner contract
live at
[docs/guide/workflows/drain-loop.md](../../docs/guide/workflows/drain-loop.md)
(t-2813, ADR-079). Read that file to run this loop; nothing here is
authoritative. This entry exists so `system/loops/` is a complete index of
every committed loop, without forking `drain-loop.md`'s procedure content
(loops-library contract, §Boundaries: "Never: duplicate `drain-loop.md`'s
procedure content into its catalog wrapper").

## Denied verbs

Single-sourced in [docs/guide/workflows/drain-loop.md](../../docs/guide/workflows/drain-loop.md)
§Denied verbs — not restated here.

**Proven:** 8-beat supervised session, 2026-08-13 (t-2813); ongoing production
use draining tagged waves since.
