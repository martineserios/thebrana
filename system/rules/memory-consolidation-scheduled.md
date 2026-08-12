---
paths: ["system/skills/memory/**", "system/skills/close/**"]
---

# Memory Consolidation Is a Scheduled Pass

Memory consolidation is a scheduled pass, not a side effect of writing a new entry.

- **On a recurring cadence** (weekly, or triggered by MEMORY.md line count): merge
  near-duplicate memory entries into one, and demote entries no session has read
  since they were written.
- **Guard the 200-line truncation limit.** MEMORY.md entries past line 200 are
  silently invisible to future sessions — a bloated, un-consolidated index disables
  every memory below the cut without any error.
- **How to apply:** run via `/brana:memory` or a dedicated consolidation pass —
  never as an implicit step inside a single `memory_write` call, which has no view
  of the whole index and can't detect duplicates.

**Why:** a single-write memory system grows unboundedly; without a scheduled merge
pass, near-duplicate entries accumulate and the 200-line index cap silently starts
dropping real content (SAFLA-inspired, t-2752).
