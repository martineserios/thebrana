---
paths: ["system/skills/memory/**", "system/skills/close/**"]
---

# Memory Decay by Non-Use

A memory's staleness signal is "never recalled since written," not "written N days ago."

- Age alone is a poor staleness proxy — a memory written 6 months ago that gets
  recalled every week is more load-bearing than one written yesterday and never
  looked up again.
- **Signal:** track recall-hit count per memory entry (via `brana recall`'s hit
  log) rather than `written_at` age.
- **How to apply:** when a consolidation/pruning pass ([[memory-consolidation-scheduled]])
  needs to pick demotion candidates, sort by recall-hit count ascending, not by
  age descending. An old, frequently-recalled memory stays; a recent,
  never-recalled one is a demotion candidate.

**Why:** age-based pruning would demote exactly the memories worth keeping — the
ones stable enough that nobody has needed to revisit or correct them recently
(SAFLA-inspired, t-2752).
