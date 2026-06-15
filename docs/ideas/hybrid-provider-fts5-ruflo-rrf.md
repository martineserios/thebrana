---
title: HybridProvider — Parallel FTS5 + Ruflo Recall with RRF Merge
status: idea
created: 2026-06-15
related_tasks: [t-2091, t-2095, t-2096]
---

# HybridProvider — Parallel FTS5 + Ruflo Recall with RRF Merge

> Brainstormed 2026-06-15. Part of the SearchProvider seam (t-2091).

## Problem

The SearchProvider seam (t-2091) defines FTS5 and ruflo as mutually exclusive backends — config picks one. Users with ruflo lose keyword precision; users without it lose semantic depth. No single call gives you combined keyword + semantic recall.

## Proposed solution

A third `SearchProvider` impl that:
- Queries FTS5Provider and RufloProvider **simultaneously** (parallel dispatch)
- Merges results with **RRF** (Reciprocal Rank Fusion, k=20)
- Degrades gracefully to FTS5-only when ruflo is absent (no error surface)

Integration:
- `brana recall <query>` CLI command — uses HybridProvider in brana-core
- `mcp__brana__recall(query)` MCP tool — thin wrapper over the CLI (standard brana pattern)

## Architecture

```
SearchProvider trait (t-2091)
├── FTS5Provider      — keyword, bundled SQLite, ruflo-free
├── RufloProvider     — semantic/vector, wraps consolidated which_ruflo() (t-2095)
└── HybridProvider    — parallel dispatch + RRF merge

HybridProvider::query(q, top_k):
  1. Query FTS5Provider and RufloProvider in parallel
  2. If ruflo absent: return FTS5 results only (fail-open, no error)
  3. RRF merge: score(hit) = 1/(k + rank_in_its_source_list), k=20
  4. Sort by RRF score descending, return top_k
  5. No dedup (stores are independent; see notes below)
```

## Key design decisions

### Not L1/L2 cache
Engram/FTS5 is NOT a cache in front of ruflo. The two stores are independent:
- FTS5 indexes `~/.claude/memory/*.md` (written by `brana memory write`)
- Ruflo's vector store contains entries written via `mcp__ruflo__memory_store`

No coherence problem because there's no cache invalidation path needed.

### Not a fallback chain
A fallback chain (ruflo → FTS5 when ruflo absent) already exists in `knowledge_pipeline.rs`
via fail-open behavior. HybridProvider is additive — parallel query, not sequential fallback.

### RRF with k=20 (not k=60)
Standard k=60 is calibrated for web-scale corpora with hundreds of results.
Brana recall returns top-10 to top-20 per provider. At k=60, rank 1 and rank 10 differ
by only 13% — almost flat. At k=20, the spread is 30%, which actually separates results.

```rust
// HybridProvider merge — ~20 lines
const K: usize = 20; // calibrated for short recall lists (~10-20 items); k=60 is web-scale
fn rrf_score(rank: usize) -> f64 {
    1.0 / (K + rank) as f64
}
// For each hit: score = rrf_score(rank_in_its_source_list)
// Accumulate per key; sort descending
```

### No dedup today
Independent stores → additive merge. If a memory appears in both FTS5 and ruflo, it
scores double in RRF — which is the correct signal (both keyword AND semantic search
found it = doubly relevant).

**Future dedup path:** When brana writes to ruflo, include `source_file` in the tags:
```rust
tags: [format!("source_file:{}", path.display())]
```
When dedup becomes needed: match FTS5 `path` field against ruflo `source_file` tag.
Zero cost today. No breaking change when added.

### No ruflo modification
Ruflo is a black box. Brana integrates via CLI shell-out (`ruflo memory search`)
and MCP calls only. The RufloProvider wraps the consolidated `which_ruflo()` from t-2095.

## Implementation sequence

1. **t-2095** (active) — consolidate `which_ruflo()` to one call site → becomes RufloProvider input
2. **t-2091** — define `SearchProvider` trait + FTS5Provider + RufloProvider impls
3. **t-2091 extension** — add HybridProvider + `brana recall` CLI command
4. **t-2096** — wire HybridProvider into skill LOAD steps + session start for proactive memory enrichment

## Engineering disciplines

- **ADR:** Extends t-2091's SearchProvider ADR. Add a "HybridProvider" section — no separate ADR.
- **Tests:** Mock both providers with fixed ranked lists, verify RRF math. Contract test suite from t-2091.
- **Docs:** `docs/architecture/field-notes/fts5-memory-recall.md` — update to mention HybridProvider. Command reference when `brana recall` is public.
