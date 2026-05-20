---
status: specifying
task: t-1492
date: 2026-05-20
produced_by: docs/ideas/memory-pattern-learning-redesign.md
depends_on:
  - docs/architecture/decisions/ADR-039-pattern-quality-filter-and-per-pattern-files.md
  - docs/architecture/features/memory-taxonomy-sdd.md
---
# Feature: Memory Pattern Learning Redesign (P0)

**Date:** 2026-05-20
**Status:** specifying
**Task:** t-1492
**ADR:** [ADR-039](../decisions/ADR-039-pattern-quality-filter-and-per-pattern-files.md)

---

## Problem

The pattern write path extracts patterns at close time without filtering for transferability.
The result is a flat `patterns.md` that mixes genuine cross-project patterns with
client-specific gotchas. A 50-entry cap forces periodic pruning that removes entries
before they can be validated as useful or garbage.

Two simultaneous failures:
1. **Write path:** no quality gate → garbage accumulates
2. **Storage model:** flat file + cap → maintenance ritual masking a write-quality problem

## Decision Record (frozen 2026-05-20)

> Do not modify after acceptance.

**Context:** patterns.md accumulated garbage (client-specific gotchas) alongside genuine
transferable patterns, with no mechanism to distinguish them. The 50-entry cap created
maintenance overhead (pruning) while the root problem (write quality) went unfixed.

**Decision:** Apply a "different codebase?" quality filter at extraction; retire flat
patterns.md in favor of per-pattern `pattern_{slug}_{date}.md` files (git-durable,
no cap). See ADR-039 for full decision record.

**Consequences:** No more pruning ritual; patterns survive ruflo corruption; MEMORY.md
grows organically with quality-filtered entries only.

---

## Scope (P0 — this build)

| Component | What changes | File(s) |
|-----------|-------------|---------|
| Quality filter | "different codebase?" gate added to extraction prompt | `debrief-analyst.md`, `retrospective.md` |
| Write path | Per-pattern files instead of flat append | `close.md` §pattern persistence |
| MEMORY.md index | NOT updated on auto-extract; only updated at manual promotion | `close.md` §pattern persistence |
| Cap/pruning | Retired — no more 50-entry cap, no more pruning step | `close.md`, `memory.md` procedure |

**Out of P0 scope:**
- Recurrence detection (P1 / t-1492 follow-up)
- Targeted sitrep recall (P2)
- Pattern indexer CLI — t-1497

---

## Constraints

- Per-pattern files must use the existing memory file frontmatter format (name, description, metadata.type)
- MEMORY.md index entry format must match the existing pattern: `- [Title](file.md) — description`
- Quality filter must err toward inclusion for borderline cases (confidence: 0.4) — curation happens at promotion time (P1), not at write time
- The `debrief-analyst` change must be backward compatible: sessions without ruflo available still write per-pattern files (graceful degradation)

---

## Design

### Quality filter gate (debrief-analyst.md + retrospective.md)

Add the transferability check as step 1 of pattern extraction:

```
For each candidate pattern extracted from the session:
  Ask: "Would this pattern apply if I were working on a completely different
        codebase with a different client?"
  - No  → reroute to field note (do not store as pattern)
  - Borderline → store with confidence: 0.4, note: "borderline transferability"
  - Yes → store with confidence: 0.5 (standard quarantine path)
```

This replaces the current unconditional extraction of all session learnings as patterns.

### Write path change (close.md)

Current path (retire):
```
Append to patterns.md. Prune to 50 entries if over cap.
```

New path:
```
1. Build slug from pattern subject (kebab-case, max 40 chars)
2. Check ruflo similarity (threshold: 0.85) for dedup
3. Write ~/.claude/projects/{hash}/memory/pattern_{slug}_{YYYY-MM-DD}.md
   (do NOT append to MEMORY.md — auto-extracted patterns are findable via
    ruflo only; MEMORY.md entries are added only at manual promotion in P1)
```

**Tier model (post-P0):**
- `pattern_*.md` files — git-durable storage, auto-extracted, not always-loaded
- `ruflo namespace:pattern` — semantic search index over pattern files
- `MEMORY.md` + `feedback_*.md` — always-loaded tier, human-curated / promoted only

This keeps MEMORY.md stable. MEMORY.md is already at 227 lines / partially truncated —
adding auto-extracted patterns to it would accelerate the problem the quality filter was
designed to solve.

### File format (per-pattern)

```markdown
---
name: {slug}
description: {one-line summary}
metadata:
  type: pattern
  confidence: 0.5
  source_task: {task-id or "manual"}
  created: YYYY-MM-DD
  transferable: true
  similar_to: {key if dedup hit, else null}
---

{pattern body — problem/solution/why, using Why:/How to apply: structure}
```

---

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Apply quality filter before any pattern write | Surface borderline cases to user | Write flat patterns.md |
| Write per-pattern files with frontmatter | Overwrite existing pattern file with same slug+date | Prune MEMORY.md by entry count |
| Append MEMORY.md pointer | | Remove pattern files from git |

---

## Testing Strategy

- **Unit:** Quality filter classification: given pattern text → field note vs pattern verdict
  (test representative garbage + genuine patterns from idea doc §Problem examples)
- **Integration:** End-to-end write path: given a pattern subject → per-pattern file created,
  frontmatter correct, MEMORY.md pointer appended
- **E2E:** Not applicable (procedure change, not a CLI command)
- **Mock policy:** No mocks needed — tests operate on temp directories

---

## Documentation Plan

- [x] **ADR-039** — `docs/architecture/decisions/ADR-039-pattern-quality-filter-and-per-pattern-files.md` (written)
- [ ] **Tech doc** — update `docs/architecture/features/memory-taxonomy-sdd.md` §Pattern type to reference per-pattern files
- [ ] **Procedure docs** — update `debrief-analyst.md`, `retrospective.md`, `close.md` (the build deliverables themselves)

---

## Challenger findings

1. **MEMORY.md growth (resolved):** Auto-appending every new pattern to MEMORY.md defeats the always-loaded tier. Fix applied: auto-extracted patterns go to `pattern_*.md` + ruflo only. MEMORY.md is updated only at explicit promotion (P1). This keeps MEMORY.md stable at its current size.

2. **Quality filter subjectivity:** The "different codebase?" question relies on LLM judgment per-extraction. Risk: over-generous classification (platform-specific patterns called universal). Mitigation: borderline path with confidence: 0.4 defers the hard cases; err toward inclusion at write time, curate at promotion time.

3. **No active consequence from retiring the cap:** The cap was the only size control on MEMORY.md. Finding #1 above replaces it with a structural separation (auto-extracted vs promoted). The cap can be safely removed.
