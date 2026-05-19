---
title: Memory Architecture Redesign — Pattern Learning that Actually Works
status: idea
created: 2026-05-19
related:
  - docs/ideas/resilient-pattern-store.md
  - docs/ideas/memory-consolidation-kairos.md
  - t-1492
  - t-608
---

# Memory Architecture Redesign — Pattern Learning that Actually Works

> Brainstormed 2026-05-19. Status: idea.

## Problem

The auto-learning system writes patterns but rarely uses them. Two simultaneous failures:

**Garbage in:** Bulk extraction at close mixes transferable patterns with client-specific gotchas.
Examples of garbage that accumulated in patterns.md before today's pruning:
- `tracy-catalog-id-not-articleid` — Tracy ERP API quirk. Useless outside proyecto_anita.
- `two-job-refresh-split` — Chess ERP Cloud Run architecture. Non-transferable.
- `momento1-requires-tiered-deal` — Kapso-specific flow logic.

Examples of signal that should have been stored:
- `hook-chain-export-list-parity` — applies to any hook chain in any project.
- `edit-separator-byte-exact` — applies every time the Edit tool is used.

**Garbage recalled:** sitrep Source 6 runs one generic query (`task_subject + branch`).
Results today: 0.43–0.45 similarity, generic patterns. Even good patterns don't surface because
the query vocabulary doesn't match the stored pattern vocabulary.

The two failures amplify each other: high noise means recall finds irrelevant patterns; poor
recall means even good patterns never change behavior.

## The quality filter

One question filters garbage from signal:

> *"Would this apply if I were working on a completely different codebase with a different client?"*

- **No** → field note. Belongs in the client's event log or a dimension doc.
- **Yes** → pattern. Proceeds to storage.

This single gate eliminates 60-70% of what currently gets extracted.

## Proposed solution

Fix both ends simultaneously using the hybrid git+ruflo model already proven by the knowledge namespace (1244 entries, survived the 2026-03-31 corruption because it's git-native).

### Component 1: Write quality gate

Change the debrief-analyst extraction prompt to apply the "different codebase?" filter before extracting patterns. Borderline cases pass through with lower confidence. Clear client-specific gotchas are re-routed to field notes.

Also dedup at write time: before storing a new pattern, check ruflo similarity (`threshold: 0.85`). Match found → increment `recurrence_count` on existing entry (don't write a duplicate). No match → new pattern.

### Component 2: Storage — per-pattern files + ruflo dual-write

Each new pattern writes to:
- `~/.claude/memory/pattern_{slug}_{date}.md` — git-durable, survives ruflo corruption
- `ruflo memory_store(namespace: "pattern")` — semantic search index

**Retire patterns.md.** No flat file, no cap, no pruning ritual. Per-pattern files scale infinitely
and can be rebuilt into ruflo on demand (same model as the knowledge namespace).

### Component 3: Recurrence → promotion path

`recurrence_count >= 3` surfaces at close: *"These patterns recurred 3+ times. Promote to
`feedback_*.md` + MEMORY.md?"*

- User approves → `feedback_{slug}.md` created + MEMORY.md index updated → always-loaded tier
- User skips → pattern stays findable via ruflo only

This replaces the quarantine/proven distinction with a concrete, data-driven promotion signal.

### Component 4: Targeted recall (sitrep Source 6)

Replace the single generic query with 3 parallel domain-specific queries per session:

1. **Domain query** — derived from `git status` file extensions:
   - `.sh` files → `"bash hook script"`
   - `.rs` files → `"Rust CLI implementation"`
   - `.md` procedures → `"procedure close documentation"`

2. **Problem-type query** — from task kind + tags:
   - kind=`bug-fix`, tag=`hook` → `"hook bug common failure modes"`
   - kind=`feature`, tag=`memory` → `"memory architecture pattern store"`

3. **Risk query** — from work type:
   - Editing hook scripts → `"hook script what goes wrong"`
   - Editing close.md → `"session close procedure failure modes"`

Merge results by key, deduplicate, suppress < 0.25 similarity.

## Sequencing (phased)

| Phase | Scope | Effort | Immediate value |
|-------|-------|--------|----------------|
| **P0** | Quality filter gate in debrief-analyst + per-pattern files replacing patterns.md | 1-2 days | Stops garbage accumulation immediately |
| **P1** | Ruflo dual-write + recurrence detection (`recurrence_count` field) | 3-4 days | Enables promotion path |
| **P2** | Targeted recall in sitrep Source 6 (3 parallel queries) | 2-3 days | Patterns actually surface when relevant |
| **P3** | Pattern indexer (rebuild ruflo from `pattern_*.md` files on demand) + Lint+Heal integration | Later | Disaster recovery; ambient curation |

## Risks

| Risk | Mitigation |
|------|------------|
| Ruflo corruption (precedent: 2026-03-31 wiped all patterns) | Git files are source of truth; indexer rebuilds ruflo from `pattern_*.md` on demand |
| Debrief-analyst over-filters, discards borderline patterns | Filter gate passes borderline cases with lower confidence; err toward inclusion at write time, curate at promotion time |
| Close.md becomes more complex | Write-path changes isolated to retrospective.md + debrief-analyst prompt; sitrep change isolated to sitrep.md Source 6; close.md itself unchanged |
| Promotion candidates pile up without user action | If user skips promotion at close, patterns remain findable via ruflo — no loss, just not in always-loaded tier |

## Engineering disciplines

- **DDD:** ADR documenting the memory tier model (Layer 0 git / ruflo semantic index / MEMORY.md always-loaded) and the quality filter rule. This is a cross-cutting architectural decision.
- **TDD:** Tests for quality filter (given pattern text → field note vs pattern classification); recurrence detection (similarity threshold behavior at write time); targeted recall (query construction from git status + task context).
- **SDD:** docs/architecture/memory.md (create); retrospective.md, close.md debrief section, sitrep.md Source 6 (update).
- **Dependency order:** ADR → quality filter → storage dual-write → recurrence → targeted recall → P3 indexer.

## Relation to prior work

- `resilient-pattern-store.md` — designed the git-native dual-write architecture after the 2026-03-31 corruption. This redesign implements that design.
- `memory-consolidation-kairos.md` — Lint+Heal scheduled curation (Karpathy methodology). P3 connects to this.
- `t-608` (Skill Registry) — long-term structural replacement for many manual pattern gates. Coordinate this redesign to not conflict.
- `t-1461` — session-state.json last-write-wins fix (write side). Parallel effort, same theme.
- `t-1491` — sitrep session-history merge (read side). Parallel effort, same theme.
