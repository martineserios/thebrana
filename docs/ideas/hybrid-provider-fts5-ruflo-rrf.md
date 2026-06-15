---
title: HybridProvider — Parallel FTS5 + Ruflo Recall with RRF Merge
status: spec-ready
created: 2026-06-15
updated: 2026-06-15
related_tasks: [t-2091, t-2095, t-2096, t-2109]
challenger_review: 2026-06-15 (8 findings — all resolved)
---

# HybridProvider — Parallel FTS5 + Ruflo Recall with RRF Merge

> Challenger-reviewed 2026-06-15. Status promoted from `idea` to `spec-ready`.
> Part of the SearchProvider seam (t-2091). Immediate prerequisite: t-2109.

## Problem

The SearchProvider seam (t-2091) defines FTS5 and ruflo as mutually exclusive backends — config picks one. Users with ruflo lose keyword precision; users without it lose semantic depth. No single call gives you combined keyword + semantic recall.

## Proposed solution

A third `SearchProvider` impl that:
- Queries FTS5Provider and RufloProvider **simultaneously** (parallel dispatch via threads)
- Merges results with **RRF** (Reciprocal Rank Fusion, k=20)
- Degrades gracefully to FTS5-only when ruflo is absent OR slow (2s deadline)
- Deduplicates by `source_file` before RRF merge

Integration:
- `brana recall <query>` CLI command — uses HybridProvider in brana-core
- `mcp__brana__recall(query)` MCP tool — thin wrapper over the CLI (standard brana pattern)

## Architecture

```
SearchProvider trait (t-2109 — immediate prerequisite)
├── FTS5Provider      — keyword, bundled SQLite, ruflo-free
├── RufloProvider     — semantic/vector, wraps ruflo_memory_search_raw() (t-2095)
└── HybridProvider    — parallel dispatch + dedup + RRF merge

HybridProvider::query(q, top_k):
  1. Spawn FTS5Provider and RufloProvider as threads
  2. Collect FTS5 results immediately (fast, SQLite)
  3. Wait up to 2s for ruflo via recv_timeout — degrade to empty on timeout
  4. Dedup by source_file: if same file appears in both stores, keep higher-ranked hit
  5. RRF merge: score(hit) = 1/(k + rank_in_its_source_list), k=20
  6. Sort by RRF score descending, return top_k
```

## Key design decisions

### Parallel dispatch: sync threads, not async

HybridProvider is implemented in **brana-core**, which is sync. `SearchProvider::query` is a sync trait method. Parallel dispatch uses `std::thread::spawn` + `mpsc::channel` + `recv_timeout`:

```rust
const HYBRID_RUFLO_DEADLINE: Duration = Duration::from_secs(2);
const K: usize = 20;

fn query(&self, q: &str, top_k: usize) -> Vec<SearchHit> {
    let fts5 = Arc::clone(&self.fts5);
    let ruflo = Arc::clone(&self.ruflo);
    let q_owned = q.to_string();

    let fts5_handle = thread::spawn(move || fts5.query(&q_owned, top_k));
    let (tx, rx) = mpsc::channel();
    thread::spawn(move || { let _ = tx.send(ruflo.query(q, top_k)); });

    let fts5_results = fts5_handle.join().unwrap_or_default();
    let ruflo_results = rx.recv_timeout(HYBRID_RUFLO_DEADLINE).unwrap_or_default();

    let merged = dedup_by_source_file(fts5_results, ruflo_results);
    rrf_merge(merged, top_k)
}
```

brana-mcp calls HybridProvider via `tokio::task::spawn_blocking` — same pattern as all other brana-core calls from the MCP layer.

**Invariant: brana-core is never made async to accommodate a transport layer.**

### 2-second ruflo deadline

The 15-second inner timeout in `ruflo_memory_search_raw()` is not an acceptable user-facing budget for an interactive CLI. HybridProvider imposes a 2-second caller-level deadline via `recv_timeout`. If ruflo misses the deadline (degraded binary, corrupted DB, stalled process), the call degrades to FTS5-only silently — same result as ruflo being absent.

This is critical for t-2096: skill LOAD steps call `brana recall`. A session with 5 skill loads on a degraded machine must not take 75 seconds (5 × 15s) to start.

### Dedup by source_file (default on)

If the same memory file appears in both FTS5 and ruflo, only the higher-ranked hit is kept. Overlap between stores reflects write-path coincidence, not query relevance — a file written via both `brana memory write` and `mcp__ruflo__memory_store` is not intrinsically more important.

Future dedup path is already zero-cost: FTS5 exposes `path`, ruflo exposes `source_file` tag. Set lookup, ~5 lines in the merge function.

### RRF with k=20 (empirically validated)

k=20 calibrated for short recall lists, not web-scale. At k=60 (standard), rank 1 vs rank 10 differ by only 13% — functionally flat at our list sizes. At k=20, spread is ~30%.

**Probe results (2026-06-15, 10 queries):**
- FTS5: caps at 20 results for general queries; 0 for impl-specific queries
- Ruflo (knowledge namespace): 3–21 results, avg ~11, top scores 0.37–0.76

k=20 validated. Score asymmetry between sparse/dense queries is real but impact is low — sparse ruflo results cluster tightly in score regardless of rank.

Threshold calibration (suppress low-quality ruflo matches) deferred to t-2109 after empirical per-namespace measurement. Do not hardcode 0.55 — knowledge namespace scores cap at ~0.50 in the current ruflo version.

### Store independence invariant

FTS5 indexes `~/.claude/memory/*.md` (written by `brana memory write`). Ruflo indexes entries written via `mcp__ruflo__memory_store`. These are independent write paths.

**Preserved invariant:** brana does not configure ruflo to watch or auto-index `~/.claude/memory/`. If this invariant is violated, RRF overlap semantics corrupt silently — dedup-by-source-file becomes a hard requirement rather than the default it already is. Record this in the t-2091 ADR.

### Not L1/L2 cache, not a fallback chain

FTS5 is NOT a cache in front of ruflo. A fallback chain (ruflo → FTS5 on absence) already exists in `knowledge_pipeline.rs`. HybridProvider is additive — parallel query on every call.

## Implementation sequence

1. **t-2095** ✓ — consolidate `which_ruflo()` → `ruflo_memory_search_raw()` canonical
2. **t-2109** — define `SearchProvider` trait + `FTS5Provider` + `RufloProvider` impls (S/M, unblocks everything below)
3. **t-2091 extension** — add `HybridProvider` + `brana recall` CLI command (blocks on t-2109)
4. **t-2096** — wire HybridProvider into skill LOAD steps + session start for proactive enrichment

**t-2096 constraint:** skill LOAD recall calls must fire in **parallel**, not sequentially. Wall-clock = max(individual calls). If serialized: 5 loads × 2s deadline = 10s blocking on session start.

## Engineering disciplines

- **ADR:** Extends t-2091's SearchProvider ADR. Add a "HybridProvider" section covering: sync dispatch rationale, 2s deadline, dedup-on semantics, store independence invariant.
- **Non-Decisions (in t-2091 ADR):** k=20 rationale (validated via 10-query probe, not arbitrary); dedup-on default (overlap = write-path coincidence, not relevance).
- **Tests:** Mock both providers with fixed ranked lists. Verify: RRF math, 2s timeout degrades to FTS5-only, dedup removes lower-ranked duplicate, empty ruflo returns FTS5 results unchanged.
- **Docs:** Update `docs/architecture/field-notes/fts5-memory-recall.md` §Recall provider model. Add `brana recall` to command reference when public.
