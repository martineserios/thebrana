---
title: "ADR-021: Knowledge Architecture v2 — Axiomatic Reflection with Temporal Awareness"
status: accepted
date: 2026-03-14
decision_makers: [martin]
---

# ADR-021: Knowledge Architecture v2

## Status

Accepted (challenged 2026-03-14, revised, accepted 2026-03-14)

## Context

The current documentation architecture (52 docs, ~28K lines, 3-layer cascade) has proven unsustainable:

- **42K-line errata log** (doc 24) with 110+ entries proves the system can't keep itself consistent
- **5 cascade commands** (`apply-errata`, `maintain-specs`, `re-evaluate-reflections`, `reconcile`, `repo-cleanup`) are too expensive to run regularly and likely to be abandoned
- **Count drift** recurs 7+ times despite the cascade pipeline existing to prevent it
- **R2 (doc 14, 65KB)** absorbs ~60% of all errata — it's simultaneously architecture spec, directory reference, hook docs, agent roster, skill catalog, and integration guide
- **95% of errata are mechanical** (stale counts, renamed skills, missing triage entries) — not reasoning errors

Meanwhile, the reflection layer's **first-principles reasoning** (the DAG: Triage → Architecture → Assurance → Lifecycle → Venture) is genuinely valuable — it forces sequential decomposition from "what matters?" through "how does it compose?" to "does it work?"

## Decision

Replace the current 3-layer cascade architecture with **Axiomatic Reflection** — documents that preserve reasoning chains with explicit assumptions, self-report health via temporal metadata, and are maintained by fitness functions embedded in existing workflows rather than dedicated cascade commands.

### Key Changes

1. **Reasoning docs replace monolithic reflections** — each doc has explicit axioms, tracked assumptions, optional IBIS structure for contested decisions, and traceable conclusions

2. **Self-reporting temporal metadata** — SemVerDoc versioning, bi-temporal fields (valid_from/valid_to), confidence tiers (tech 6mo / architecture 18mo / methodology 36mo), maturity stages (seedling/budding/evergreen)

3. **Embedded changelogs replace doc 24** — each doc carries its own append-only changelog. No external errata log needed.

4. **Field notes section** — practical learnings from work sessions appended to relevant docs. Lifecycle: promote / relate / trigger research / contradict assumption / archive.

5. **Lightweight ontology** — 5 entity types, 5 typed relationship types in `brana-ontology.yaml` (minimal viable — extend when ambiguity proves it). Typed links in markdown replace untyped `[doc NN](path)`.

6. **Extended spec-graph** — existing spec-graph.json (159 nodes, 483 edges) gains typed edges (assumes, implements, enriches, contradicts, etc.)

7. **Multi-namespace ruflo indexing** — new namespaces: `assumptions`, `field-notes`, `decisions`. Indexed via on-commit hook + weekly full reindex.

8. **Internal-first research** — `/brana:research` Phase 0 queries all ruflo namespaces + spec-graph before any web search.

9. **Fitness functions in validate.sh** — checks 15-22: assumption freshness, changelog currency, status consistency, graph integrity, scale triggers.

10. **Work IS maintenance** — every command (`/build`, `/close`, `/research`, etc.) maintains knowledge as a side effect. No dedicated maintenance commands.

11. **Automated cadence via scheduler** — morning-check, weekly-review, monthly knowledge-review, assumption-health, scale-triggers, field-notes-review all run automatically.

12. **Scale triggers** — deferred features (AgentDB Cypher, GraphRAG, witness chains, temperature tiering, reflexion) activate automatically when thresholds cross, auto-creating backlog tasks.

### Reflection Disposition

| Current | Becomes |
|---|---|
| R1 (08 Triage, 33KB) | ADR-020 + assumptions list |
| R2 (14 Architecture, 65KB) | Split: ~25KB reasoning (ARCHITECTURE.md) + generated component-index.md |
| R3 (31 Assurance, 18KB) | ASSURANCE.md + fitness functions in validate.sh |
| R4 (32 Lifecycle, 23KB) | LIFECYCLE.md — add axioms, assumptions, changelog |
| R5 (29 Venture, 50KB) | VENTURE.md — add axioms, assumptions, changelog |
| Doc 24 (42K errata) | Killed — replaced by per-doc changelogs |
| Doc 17 (superseded roadmap) | Archived |

### Commands Disposition

| Current | Becomes |
|---|---|
| `/brana:apply-errata` | Kill — no errata log |
| `/brana:maintain-specs` (10 steps) | Replace with `/brana:verify-docs` (fitness checks + flag) |
| `/brana:re-evaluate-reflections` | Merge into verify-docs |
| `/brana:reconcile` | Keep (simplified — traces typed deps) |
| `/brana:repo-cleanup` | Keep |

## Alternatives Considered

### 1. "Reflection as Query" (full elimination of synthesis)

Generate all synthesis on-demand via AI + semantic search. No hand-maintained docs.

Rejected because: Scout 2 research found synthesis layers ARE still needed — flat RAG fails on complex reasoning. R2's 50KB of "why things compose this way" is genuine reasoning, not retrievable facts. On-demand synthesis can't reconstruct cross-cutting architectural arguments.

### 2. Keep current system, fix cascade commands

Make the 5-command pipeline more reliable.

Rejected because: the pipeline's cost (40-60% context per run) exceeds the cost of the drift it catches. 110 errata entries prove the pipeline can't keep up. The problem is structural, not operational.

### 3. ADR-only (no reasoning docs)

Replace all reflections with ADRs. Let AI synthesize cross-cutting patterns at query time.

Rejected because: ADRs capture individual decisions but not how decisions interact — the "Wikipedia problem." The three-layer architecture emerges from ADR-005 + ADR-006 + ADR-015 + hook lifecycle + context engineering research. No single ADR contains the system-level picture.

### 4. Full IBIS + ATMS formalization

Formalize every decision as Issue → Position → Argument with assumption-based truth maintenance.

Rejected as default because: 95% of brana's errata are bookkeeping, not reasoning failures. IBIS is overkill for non-contested decisions. Kept as opt-in for genuinely contested choices.

## Consequences

### Positive

- Doc maintenance embedded in normal work — no dedicated commands to remember
- Self-reporting docs surface their own staleness
- Field notes close the "practice → theory" feedback loop
- Typed relationships enable multi-hop queries
- Scale triggers prevent premature optimization AND ensure timely activation
- ~28K lines → ~12-15K lines (reasoning preserved, inventory auto-generated)

### Negative

- Migration effort: ~7-8 sessions across 9 phases
- Novel approach (no published precedent for "axiomatic reflection")
- R2 split requires judgment call on what's "reasoning" vs "inventory"
- Assumption tracking adds per-doc overhead (~10 lines frontmatter)

### Risks

- On-demand synthesis quality for generated component-index.md
- Fitness functions catch structural drift but not semantic drift
- Confidence tiers may need recalibration after first 6 months
- Cold-start problem: first sessions after migration have reduced context

### Second Phase (deferred with triggers)

Second-phase items are tracked as tasks (t-429 through t-436) with explicit activation triggers. Scale triggers run monthly via validate.sh + scheduler. Feature maturity triggers (field notes lifecycle, confidence tiers) run on time-based review. No manual tracking required — scheduler surfaces them.

See feature brief for full second-phase table with triggers and task IDs.

## Implementation

See feature brief: [knowledge-architecture-v2.md](../features/knowledge-architecture-v2.md)

13 phases (0-12), each independently valuable, ~1 session each. No big-bang migration. Phases 10-11 add user guide and tech docs. Phase 12 kills cascade commands after 2-week soak.

### Assumptions

| # | Claim | If Wrong | Last Verified |
|---|---|---|---|
| 1 | Solo operator maintains 3 new frontmatter fields | Fields go stale; validate.sh flags missing/stale | 2026-03-14 |
| 2 | /brana:close runs consistently | Field notes never appended; session-end hook fallback | 2026-03-14 |
| 3 | Semantic drift is rare enough for structural checks | Docs say X, code does Y; quarterly manual review | 2026-03-14 |
| 4 | 160 nodes won't hit 500 in 6 months | Scale trigger fires too early; ~280 in 12mo realistic | 2026-03-14 |
| 5 | brana-knowledge stays separate repo | Cross-repo field notes need coordination; post-commit hook | 2026-03-14 |
| 6 | Claude consistently applies ontology types | Typed links inconsistent; validate.sh + PreToolUse warning | 2026-03-14 |
