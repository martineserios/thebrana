---
status: proposed
produced_by: docs/ideas/memory-pattern-learning-redesign.md
depends_on:
  - docs/architecture/decisions/ADR-038-memory-write-gateway.md
  - docs/architecture/features/memory-taxonomy-sdd.md
---
# ADR-039: Pattern Quality Filter + Per-Pattern File Storage

**Status:** Proposed
**Date:** 2026-05-20
**Task:** t-1492 (memory-arch initiative)
**Depends on:** ADR-038 (write gateway), memory-taxonomy-sdd.md (classify() interface)

---

## Context

The auto-learning system extracts patterns at close time and stores them. Two simultaneous failures make the system unreliable:

**Garbage in (write path):** Bulk extraction mixes transferable patterns with client-specific gotchas.
Examples of garbage that accumulated before 2026-05-20 pruning:
- `tracy-catalog-id-not-articleid` — Tracy ERP API quirk, useless outside proyecto_anita
- `two-job-refresh-split` — Chess ERP Cloud Run architecture, non-transferable
- `momento1-requires-tiered-deal` — Kapso-specific flow logic

Examples of genuine signal that was mixed in:
- `hook-chain-export-list-parity` — applies to any hook chain in any project
- `edit-separator-byte-exact` — applies every time the Edit tool is used

**Cap maintenance overhead (storage):** `patterns.md` with a 50-entry cap requires manual
chronological pruning. Pruning removes knowledge before validation (an entry pruned at
position 51 may be the one that prevents a repeated mistake). The cap is an operational
ritual masking a write-quality problem.

**Root cause:** The extraction step does not distinguish "transferable tool/process pattern"
from "client-specific gotcha." Without that distinction, the storage model (flat file, capped)
cannot work regardless of how well it is maintained.

---

## Decision

### 1. Quality filter at extraction time

Apply a single gate before any pattern is stored:

> *"Would this pattern apply if I were working on a completely different codebase with a different client?"*

- **No** → route to field note (client event log, or dimension doc §Field Notes). Do not store as pattern.
- **Borderline** → store with `confidence: 0.4` (lower than default 0.5). Label as borderline.
- **Yes** → store as pattern at `confidence: 0.5` (quarantine, standard path).

This gate is applied in the `debrief-analyst` extraction prompt and in the `retrospective.md`
procedure when the user manually stores a pattern.

### 2. Per-pattern files replacing flat patterns.md

Each new pattern writes to a dedicated file:
```
~/.claude/projects/{project-hash}/memory/pattern_{slug}_{date}.md
```

**File format:**
```markdown
---
name: {slug}
description: {one-line summary}
metadata:
  type: pattern
  confidence: 0.5
  source_task: t-NNN
  created: YYYY-MM-DD
  transferable: true
---

{pattern body — problem/solution/why}
```

**MEMORY.md index:** Auto-extracted patterns are NOT added to MEMORY.md.
MEMORY.md is the always-loaded tier and contains only human-curated or promoted entries.
Auto-extracted patterns are discoverable via ruflo semantic search; MEMORY.md entry is
added only at explicit promotion (P1 recurrence path). This preserves the context budget
(MEMORY.md already at 227 lines / partially truncated at session load).

**Retire flat patterns.md.** No flat file, no cap, no pruning ritual. Per-pattern files
scale without maintenance overhead and survive ruflo corruption (git-durable).

### 3. Dedup at write time

Before creating a new pattern file, check ruflo similarity:
```
mcp__ruflo__memory_search(query: "{pattern summary}", namespace: "pattern", limit: 1, threshold: 0.85)
```
- Match found → increment recurrence count on existing entry (P1 — not in P0 scope). For P0: log "similar pattern exists: {key}" in the new file's frontmatter and proceed.
- No match → write new file normally.

---

## Consequences

**Positive:**
- Quality filter eliminates 60–70% of current garbage at the source
- Per-pattern files are git-durable: ruflo corruption (precedent: 2026-03-31) no longer loses patterns
- No cap means no pruning ritual — maintenance cost drops to near zero
- MEMORY.md index grows organically; entries are meaningful because the filter runs first

**Negative / trade-offs:**
- MEMORY.md grows longer over time (no cap). Mitigated by: (a) filter eliminates most candidates,
  (b) MEMORY.md is already at 227 lines — the problem is entry quality, not entry count.
- Dedup check adds one ruflo query per pattern write. Acceptable: write happens at close, not in hot path.

---

## Non-Actions (P0 scope boundary)

The following are intentionally deferred to later phases:

- **Recurrence detection** (`recurrence_count` field, auto-increment on dedup hit) — P1
- **Promotion path** (`recurrence >= 3` → surface to feedback_*.md → MEMORY.md always-loaded tier) — P1
- **Targeted recall in sitrep Source 6** (3 parallel domain-specific queries) — P2
- **Pattern indexer CLI** (`brana patterns rebuild` from `pattern_*.md` files) — P3 (tracked as t-1497)
- **Lint+Heal scheduled curation** (Karpathy methodology) — P3 / memory-consolidation-kairos.md

These are not excluded because they are wrong — they are excluded because P0 delivers the
highest-value change (stop the garbage) with the smallest surface area.

---

## Relation to prior decisions

- **ADR-037** (enforcement waves): the quality filter is compatible — it's a write-path change,
  not a routing change. The enforcement hook still blocks direct feedback_*.md writes.
- **ADR-038** (write gateway): the quality filter sits upstream of the gateway classify() call.
  Pattern files use the same CLI gateway path as other memory types.
- **memory-taxonomy-sdd.md**: the `pattern` type in the 6-type taxonomy maps to the per-pattern
  file destination defined here. No taxonomy change needed.
- **t-608** (Skill Registry): this redesign is compatible. Pattern files are agnostic to how
  skills are discovered. Coordinate at t-608 implementation time to avoid conflating pattern
  recall with skill suggestion.
