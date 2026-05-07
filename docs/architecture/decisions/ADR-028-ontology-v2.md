---
depends_on:
  - docs/architecture/decisions/ADR-021-knowledge-architecture-v2.md
  - docs/architecture/features/operating-model.md
informs:
  - docs/brana-ontology.yaml
  - docs/architecture/decisions/ADR-027-auto-learning-loop.md
  - docs/architecture/decisions/ADR-030-maintenance-unification.md
status: accepted
---

# ADR-028: Ontology v2 (Measurement-Gated)

**Date:** 2026-04-04
**Status:** accepted
**Tasks:** t-897
**Source:** Operating model §12, extends ADR-021 (Knowledge Architecture v2)

## Context

ADR-021 established a knowledge architecture with 5 entity types and 5 relationship types. Working with the system revealed gaps: no vocabulary for classifying EXTRACT findings, no typed edges for graph traversal during LOAD, no axioms for automated consistency checks.

Research into knowledge graph patterns (Cognee, Lindenberg, Vanderseypen) and the operating model design surfaced a richer ontology: 15 entity types, 11 relationships, 6 axioms. However, the challenger review flagged that shipping all 15 types contradicts the "simplicity wins" meta-pattern. Shipping 15 types upfront means most will go unused.

## Decision

Ship a YAML ontology spec at `docs/brana-ontology.yaml` with 15 entity types, 11 relationships, and 6 axioms. Track usage via session state metrics. Demote zero-usage types after 30 days.

### Three Layers

```
ONTOLOGY (stable schema — rarely changes)
  docs/brana-ontology.yaml: types, relationships, axioms

FRONTMATTER (instance data — grows every session via PERSIST)
  Each markdown file's YAML: typed relationships (depends_on, informs, etc.)

GRAPH (computed — auto-recomputes on commit, never manually edited)
  docs/spec-graph.json: typed nodes + typed edges + axiom-derived edges
```

### Phase A: Start with 5+3

Per challenger recommendation, Phase A uses only the 5 types from ADR-021 plus 3 core relationships. The full 15 types are documented in the YAML but not actively processed until usage data justifies expansion.

| Phase | Types | Relationships |
|-------|-------|---------------|
| **A (Month 1)** | Dimension, Reflection, ADR, Pattern, Roadmap | depends_on, informs, supersedes |
| **B (Month 2)** | + FieldNote, Assumption, Constraint | + contradicts, implements, applies_to |
| **Full (Month 3+)** | All 15 (measurement-gated) | All 11 (measurement-gated) |

### Usage Tracking

Session state JSON accumulates:
```json
"ontology_metrics": {
  "types_loaded": ["Dimension", "ADR"],
  "types_extracted": ["Pattern"],
  "types_persisted": ["FieldNote"],
  "relationships_traversed": ["depends_on"],
  "relationships_written": ["informs"]
}
```

Types with zero usage across all sessions in 30 days are demoted from active graph processing. The YAML retains all types as documentation.

### How Ontology Powers the Auto-Learning Loop

| Loop Step | Ontology Role |
|-----------|--------------|
| LOAD | Follow typed edges (informs, depends_on) — not just vector similarity |
| EXTRACT | Entity types = vocabulary for classifying findings |
| EVALUATE | Axioms power the quality gate (contradicts → flag, supersedes → auto-status) |
| PERSIST | Entity types determine WHERE to store; writes frontmatter relationships |
| DECAY | Graph-aware pruning: orphan nodes, stale nodes, contradiction detection |

### 6 Axioms

1. **Transitivity:** depends_on is transitive (A→B→C means A→C)
2. **Supersession chain:** supersedes must form complete chains (no gaps)
3. **Contradiction flag:** contradicts triggers LARGE evaluation
4. **Single source:** each fact has exactly one authoritative source
5. **Staleness:** >90 days + no search hits → stale warning
6. **Orphan detection:** nodes with zero edges are flagged for review

## Consequences

- `docs/brana-ontology.yaml` becomes the single schema definition
- Frontmatter in markdown docs gains typed relationship fields
- spec-graph.json gains typed nodes and typed edges (via `brana graph` CLI, Phase D)
- Current 211 untyped nodes / 568 untyped edges migrate incrementally
- Obsidian and Claude Code share the same files — no sync needed
- Measurement-gated expansion prevents unused type bloat
