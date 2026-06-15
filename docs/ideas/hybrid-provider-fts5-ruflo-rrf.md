---
title: HybridProvider — Parallel FTS5 + Ruflo Recall with RRF Merge
status: spec-ready
created: 2026-06-15
updated: 2026-06-15
related_tasks: [t-2091, t-2095, t-2096, t-2109]
challenger_review: 2026-06-15 (8 findings — all resolved, second pass 2026-06-15)
---

# HybridProvider — Parallel FTS5 + Ruflo Recall with RRF Merge

> Challenger-reviewed 2026-06-15 (pass 1: 8 findings). Six Thinking Hats pass 2026-06-15 (8 findings — all resolved).
> Status: spec-ready. Part of the SearchProvider seam (t-2091). Immediate prerequisite: t-2109.

## Problem

The SearchProvider seam (t-2091) defines FTS5 and ruflo as mutually exclusive backends — config picks one. Users with ruflo lose keyword precision; users without it lose semantic depth. No single call gives you combined keyword + semantic recall.

## Proposed solution

A third `SearchProvider` impl that:
- Queries FTS5Provider and RufloProvider **simultaneously** (parallel dispatch via threads)
- Merges results with **RRF** (Reciprocal Rank Fusion, k=20) across both full lists
- Degrades gracefully to FTS5-only when ruflo is absent OR slow (2s deadline)
- Degrades gracefully to empty when FTS5 is slow (500ms deadline)

Integration:
- `brana recall <query>` CLI command — calls HybridProvider directly via brana-core
- `mcp__brana__recall(query)` MCP tool — calls HybridProvider via `tokio::task::spawn_blocking` (same as all other brana-core calls from the MCP layer)

## Architecture

```
SearchProvider trait (t-2109 — immediate prerequisite)
├── FTS5Provider      — keyword, bundled SQLite, ruflo-free
├── RufloProvider     — semantic/vector, wraps ruflo_memory_search_raw() (t-2095)
└── HybridProvider    — parallel dispatch + RRF merge across full lists

HybridProvider::query(q, top_k):
  1. Convert q: &str → Arc<str> (one allocation, shared across threads)
  2. Spawn FTS5Provider and RufloProvider as threads, each receiving Arc::clone
  3. Wait up to 500ms for FTS5 via recv_timeout — degrade to empty on timeout
  4. Wait up to 2s for ruflo via recv_timeout — degrade to empty on timeout
  5. RRF merge across both full lists: score(doc) = Σ 1/(k + rank_in_source_list)
     — documents appearing in both lists receive additive contributions (correct behavior)
  6. Sort by RRF score descending, return top_k
```

No dedup step. RRF handles overlap by design — a document ranking high in both keyword and semantic search is genuinely more relevant, not an artifact to suppress.

## Key design decisions

### Parallel dispatch: sync threads + Arc<str>, not async

HybridProvider lives in **brana-core**, which is sync. `SearchProvider::query` is a sync trait method. Parallel dispatch uses `std::thread::spawn` + `mpsc::channel` + `recv_timeout`.

The query string is converted to `Arc<str>` once at the dispatch boundary. Each thread receives an `Arc::clone` — zero-copy, one heap allocation regardless of provider count. The trait stays `&str` (ergonomic for all callers); the `Arc` is an implementation detail of HybridProvider.

```rust
const FTS5_DEADLINE:  Duration = Duration::from_millis(500);
const RUFLO_DEADLINE: Duration = Duration::from_secs(2);
const K: usize = 20;

fn query(&self, q: &str, top_k: usize) -> Vec<SearchHit> {
    let q: Arc<str> = Arc::from(q);

    let fts5  = Arc::clone(&self.fts5);
    let ruflo = Arc::clone(&self.ruflo);
    let q_fts5  = Arc::clone(&q);
    let q_ruflo = Arc::clone(&q);

    let (tx_fts5,  rx_fts5)  = mpsc::channel();
    let (tx_ruflo, rx_ruflo) = mpsc::channel();

    thread::spawn(move || { let _ = tx_fts5.send(fts5.query(&q_fts5, top_k)); });
    thread::spawn(move || { let _ = tx_ruflo.send(ruflo.query(&q_ruflo, top_k)); });

    let fts5_results  = rx_fts5.recv_timeout(FTS5_DEADLINE).unwrap_or_default();
    let ruflo_results = rx_ruflo.recv_timeout(RUFLO_DEADLINE).unwrap_or_default();

    rrf_merge(vec![fts5_results, ruflo_results], K, top_k)
}
```

brana-mcp calls HybridProvider via `tokio::task::spawn_blocking` — same pattern as all other brana-core calls from the MCP layer.

**Invariant: brana-core is never made async to accommodate a transport layer.**

### Symmetric deadlines: FTS5 500ms, ruflo 2s

Both providers have bounded latency via the same channel + `recv_timeout` pattern.

**FTS5 deadline (500ms):** SQLite is local and expected fast, but can stall under WAL checkpoint, write lock contention (`SQLITE_BUSY`), or I/O saturation. 500ms is a conservative upper bound for a local SQLite read. Timeout degrades to empty — same as ruflo absent.

**Ruflo deadline (2s):** The 15-second inner timeout in `ruflo_memory_search_raw()` is not an acceptable user-facing budget for an interactive CLI. HybridProvider imposes a 2-second caller-level deadline. If ruflo misses it (degraded binary, corrupted DB, stalled process), the call degrades to FTS5-only silently.

This is critical for t-2096: skill LOAD steps call `brana recall`. A session with 5 skill loads on a degraded machine must not take 75 seconds (5 × 15s) to start.

Deadlines are separate named constants — independently motivated, not a shared budget. If FTS5 is slow for unrelated reasons (disk I/O spike), it does not steal ruflo's budget.

**Known limitation:** Both provider threads run to their respective inner timeouts after HybridProvider degrades. `JoinHandle` is intentionally dropped — Rust provides no cancellation API for blocking threads. At current call volumes (≤5 parallel LOAD calls), steady-state leak is ~2–3 threads, all blocking on IPC, no CPU cost. Architectural resolution: ruflo as a long-running daemon with socket-level timeout — socket close propagates cancellation through the OS. Track under t-2091 ADR §Future.

### RRF with k=20 — no dedup (full lists)

RRF runs across both **full** provider lists. No dedup step before merge.

**Why no dedup:** RRF is designed to merge ranked lists. A document appearing in both FTS5 (keyword match) and ruflo (semantic match) for the same query receives additive RRF contributions:

```
score(doc) = 1/(k + rank_fts5) + 1/(k + rank_ruflo)
```

This is correct behavior — dual-signal confirmation is genuine relevance, not write-path noise. Dedup-before-RRF destroys this signal while solving a problem (write-path overlap) that the store independence invariant already prevents at the right layer.

**k=20 calibration basis:** Chosen for list lengths of 3–21 (avg 11). At k=20 and list length 20, spread between rank 1 and rank 20 is ~47%. At k=60 (web-scale default), spread is ~24% — functionally flat for lists this short.

Probe: 10 queries, actual corpus, 2026-06-15.
- FTS5: caps at 20 results for general queries; 0 for impl-specific
- Ruflo (knowledge namespace): 3–21 results, avg ~11, top scores 0.37–0.76

k=20 confirmed appropriate for current corpus. **Re-examine when average ruflo result count exceeds 30 per query.** At that threshold, k=20 may over-penalize lower ranks. Re-validation: 20 queries across types (specific, general, impl-specific), plot score distribution, verify top-5 are meaningfully differentiated from rank 6–10.

Threshold calibration (suppress low-quality ruflo matches) deferred to t-2109 after empirical per-namespace measurement. Do not hardcode 0.55 — knowledge namespace scores cap at ~0.50 in the current ruflo version.

### Store independence invariant

FTS5 indexes `~/.claude/memory/*.md` (written by `brana memory write`). Ruflo indexes entries written via `mcp__ruflo__memory_store`. These are independent write paths.

**Preserved invariant:** brana does not configure ruflo to watch or auto-index `~/.claude/memory/`. This invariant is the enforcement point for write-path overlap control — not the RRF merge function. Validated by integration test (no document ID appears in both stores at session start). Record in t-2091 ADR.

If this invariant is violated, RRF scores inflate uniformly across all overlapping documents. Relative ranking is preserved even under inflation, but the violation should be caught by the integration test, not compensated by the ranking layer.

### SearchHit path normalization (t-2109 scope)

`SearchHit.source_file` must be a canonical absolute path, normalized at construction time by each provider impl — not at merge time. Both FTS5 (`path` field) and ruflo (`source_file` tag) normalize via `fs::canonicalize` when constructing `SearchHit`. Canonicalization failures (stale index entries) degrade to raw path, not panic. This ensures consistent path representation for all downstream consumers regardless of which provider is active. Enforced in t-2109.

### MCP integration: spawn_blocking, not shell-out

`mcp__brana__recall` calls `HybridProvider::query()` via `tokio::task::spawn_blocking` — same as every other brana-core call in brana-mcp. It does not shell out to the `brana recall` CLI.

The CLI and MCP tool are parallel consumers of the same library function. Neither wraps the other. "Thin wrapper over CLI" applies only to legacy MCP tools where logic lives in the binary rather than brana-core.

### Not L1/L2 cache, not a fallback chain

FTS5 is NOT a cache in front of ruflo. A fallback chain (ruflo → FTS5 on absence) already exists in `knowledge_pipeline.rs`. HybridProvider is additive — parallel query on every call.

## Implementation sequence

1. **t-2095** ✓ — consolidate `which_ruflo()` → `ruflo_memory_search_raw()` canonical
2. **t-2109** — define `SearchProvider` trait + `FTS5Provider` + `RufloProvider` impls, `SearchHit` with canonical path normalization (S/M, unblocks ADR draft)
3. **ADR update (t-2091)** — add HybridProvider section: sync dispatch rationale, k=20 probe, dedup-dropped rationale, store independence invariant, MCP integration choice, deadline values, non-decisions table. Blocks t-2091 extension. Draft after t-2109 trait shape is concrete.
4. **t-2091 extension** — add `HybridProvider` + `brana recall` CLI command (blocked by t-2109 + ADR update)
5. **t-2096** — wire HybridProvider into skill LOAD steps + session start for proactive enrichment (blocked by t-2091 extension)

**t-2096 constraint:** skill LOAD recall calls must fire in **parallel**, not sequentially. Wall-clock = max(individual calls). If serialized: 5 loads × 2s deadline = 10s blocking on session start.

## Engineering disciplines

- **ADR:** Extends t-2091's SearchProvider ADR. Add HybridProvider section (step 3 above, blocking impl). Non-decisions table must include: k=60 rejected (flat at short list lengths), dedup-before-RRF rejected (destroys dual-signal confirmation, wrong layer for overlap control), shell-out rejected (spawn_blocking already available), Arc<str> on trait rejected (leaks threading concern into abstraction), shared deadline budget rejected (provider independence).
- **Tests:** Mock both providers with fixed ranked lists. Verify: RRF math across full lists (no dedup), 500ms FTS5 timeout degrades to empty, 2s ruflo timeout degrades to FTS5-only, empty ruflo returns FTS5 results unchanged, empty FTS5 returns ruflo results unchanged, document in both lists scores higher than document in one list (dual-signal confirmation).
- **Docs:** Update `docs/architecture/field-notes/fts5-memory-recall.md` §Recall provider model. Add `brana recall` to command reference when public.
