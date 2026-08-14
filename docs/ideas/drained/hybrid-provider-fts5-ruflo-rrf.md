---
title: HybridProvider — Parallel FTS5 + Ruflo Recall with RRF Merge
status: spec-ready
created: 2026-06-15
updated: 2026-06-15
related_tasks: [t-2091, t-2095, t-2096, t-2109]
challenger_review: 2026-06-15 (8 findings — all resolved, second pass 2026-06-15, third pass 2026-06-15 — 7 findings, all resolved)
---

# HybridProvider — Parallel FTS5 + Ruflo Recall with RRF Merge

> Challenger-reviewed 2026-06-15 (pass 1: 8 findings). Six Thinking Hats pass 2026-06-15 (8 findings — all resolved). Third adversarial pass 2026-06-15 (7 findings — all resolved).
> Status: spec-ready. Part of the SearchProvider seam (t-2091). Immediate prerequisite: t-2109.

## Problem

The SearchProvider seam (t-2091) defines FTS5 and ruflo as mutually exclusive backends — config picks one. Users with ruflo lose keyword precision; users without it lose semantic depth. No single call gives you combined keyword + semantic recall.

## Proposed solution

A third `SearchProvider` impl that:
- Queries FTS5Provider and RufloProvider **simultaneously** (parallel dispatch via threads)
- Merges results with **RRF** (Reciprocal Rank Fusion, k=20) across both full lists
- Degrades gracefully to FTS5-only when ruflo is absent OR slow (2s deadline)
- Degrades gracefully to ruflo-only results when FTS5 is slow (500ms deadline)

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
  2. Spawn FTS5Provider and RufloProvider as threads, each fetching MIN_CANDIDATE_POOL results
  3. Wait up to 500ms for FTS5 — degrade to ruflo-only on timeout
  4. Wait up to 2s for ruflo (budget from dispatch start) — degrade to FTS5-only on timeout
  5. RRF merge across both candidate lists: score(doc) = Σ 1/(k + rank_in_source_list)
     — DocRef identity ensures no cross-backend false dedup
  6. Sort by RRF score descending, truncate to top_k
```

No dedup step. RRF handles overlap by design — a document ranking high in both keyword and semantic search is genuinely more relevant, not an artifact to suppress.

## Key design decisions

### Parallel dispatch: sync threads + Arc<str>, not async

HybridProvider lives in **brana-core**, which is sync. `SearchProvider::query` is a sync trait method. Parallel dispatch uses `std::thread::spawn` + `mpsc::channel` + `recv_timeout`.

The query string is converted to `Arc<str>` once at the dispatch boundary. Each thread receives an `Arc::clone` — zero-copy, one heap allocation regardless of provider count. The trait stays `&str` (ergonomic for all callers); the `Arc` is an implementation detail of HybridProvider.

```rust
const FTS5_DEADLINE:      Duration = Duration::from_millis(500);
const RUFLO_DEADLINE:     Duration = Duration::from_secs(2);
const K:                  usize    = 20;
const MIN_CANDIDATE_POOL: usize    = 20;

fn query(&self, q: &str, top_k: usize) -> Vec<SearchHit> {
    let q: Arc<str> = Arc::from(q);
    let fetch = top_k.max(MIN_CANDIDATE_POOL);

    let fts5  = Arc::clone(&self.fts5);
    let ruflo = Arc::clone(&self.ruflo);
    let q_fts5  = Arc::clone(&q);
    let q_ruflo = Arc::clone(&q);

    let (tx_fts5,  rx_fts5)  = mpsc::channel();
    let (tx_ruflo, rx_ruflo) = mpsc::channel();

    thread::spawn(move || { let _ = tx_fts5.send(fts5.query(&q_fts5, fetch)); });
    thread::spawn(move || { let _ = tx_ruflo.send(ruflo.query(&q_ruflo, fetch)); });

    // Shared deadline: ruflo budget starts from dispatch, not from when FTS5 returns.
    // Worst-case wall-clock = RUFLO_DEADLINE (2s), not FTS5_DEADLINE + RUFLO_DEADLINE (2.5s).
    let start = std::time::Instant::now();
    let fts5_results  = rx_fts5.recv_timeout(FTS5_DEADLINE).unwrap_or_default();
    let ruflo_budget  = RUFLO_DEADLINE.saturating_sub(start.elapsed());
    let ruflo_results = rx_ruflo.recv_timeout(ruflo_budget).unwrap_or_default();

    rrf_merge(vec![fts5_results, ruflo_results], K, top_k)
}
```

brana-mcp calls HybridProvider via `tokio::task::spawn_blocking` — same pattern as all other brana-core calls from the MCP layer.

**Invariant: brana-core is never made async to accommodate a transport layer.**

**FTS5Provider connection constraint:** `FTS5Provider` MUST open a new `rusqlite::Connection` per `query()` call via `Connection::open(&self.db_path)`. It MUST NOT hold a `Connection` as struct state. `Arc::clone(&self.fts5)` is passed into `thread::spawn`, which requires `FTS5Provider: Send + Sync`. `rusqlite::Connection` is `!Send` — holding one as struct state causes a compile error. Connection-per-query is the correct pattern; connection pooling via `Mutex<Connection>` would serialize provider calls and defeat parallel dispatch.

### Symmetric deadlines: FTS5 500ms, ruflo 2s

Both providers have bounded latency via the same channel + `recv_timeout` pattern.

**FTS5 deadline (500ms):** SQLite is local and expected fast, but can stall under WAL checkpoint, write lock contention (`SQLITE_BUSY`), or I/O saturation. 500ms is a conservative upper bound for a local SQLite read. Timeout degrades to empty — same as ruflo absent.

**Ruflo deadline (2s):** The 15-second inner timeout in `ruflo_memory_search_raw()` is not an acceptable user-facing budget for an interactive CLI. HybridProvider imposes a 2-second caller-level deadline. If ruflo misses it (degraded binary, corrupted DB, stalled process), the call degrades to FTS5-only silently.

This is critical for t-2096: skill LOAD steps call `brana recall`. A session with 5 skill loads on a degraded machine must not take 75 seconds (5 × 15s) to start.

Deadlines are separate named constants — independently motivated, not a shared budget. If FTS5 is slow for unrelated reasons (disk I/O spike), it does not steal ruflo's budget.

**Known limitation:** Both provider threads run to their respective inner timeouts after HybridProvider degrades. `JoinHandle` is intentionally dropped — Rust provides no cancellation API for blocking threads. Each `query()` call that exceeds a deadline leaks up to 2 threads (one per provider), each blocking until that provider's inner timeout expires. Peak concurrent leaked threads = 2 × (calls that timed out within the last 15s). At current call volumes (≤5 LOAD calls per session start, ≤1 MCP recall per turn), steady-state peak is ≤10 threads, all blocking on IPC, no CPU cost. Re-evaluate if per-turn MCP recall frequency increases significantly. Architectural resolution: ruflo as a long-running daemon with socket-level timeout — socket close propagates cancellation through the OS. Track under t-2091 ADR §Future.

### RRF with k=20 — no dedup (full candidate pool)

RRF runs across both provider lists fetched at `MIN_CANDIDATE_POOL` depth (20), regardless of the caller's `top_k`. Only the final RRF output is truncated to `top_k`. No dedup step before merge.

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

**Preserved invariant:** brana does not configure ruflo to watch or auto-index `~/.claude/memory/`. `DocRef::MemoryFile` and `DocRef::KnowledgeEntry` are disjoint by type — cross-backend identity collision is structurally impossible at the Rust level. The invariant enforces this at the write path for the case where ruflo's external configuration changes (e.g., a future ruflo version adds auto-directory-watching).

**Two-layer test (record in t-2091 ADR):**
1. **Write-path test (config-level):** assert that `ruflo config show` contains no watch path pointing to `~/.claude/memory/` or `~/.claude/projects/*/memory/`. Catches configuration drift before it produces results.
2. **Read-time smoke test (session start):** assert that no ruflo key in the `knowledge` or `pattern` namespace matches a `slug` value from the FTS5 index. Catches auto-indexing drift that bypasses config-level detection.

If this invariant is violated, both test layers fire. The ranking layer does not compensate — the invariant must be enforced at the write path.

### SearchHit identity model (t-2109 scope)

FTS5 and ruflo use fundamentally different document identity systems. FTS5 indexes filesystem files; ruflo indexes semantic knowledge entries keyed by content ID. These are never the same document — the store independence invariant enforces this at the write path. `SearchHit` represents both without fiction via a typed document reference:

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum DocRef {
    MemoryFile     { path: PathBuf, slug: String, mtype: String, scope: String },
    KnowledgeEntry { key: String, namespace: String },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchHit {
    pub doc:      DocRef,
    pub snippet:  String,
    pub rrf_score: f64,
}
```

**RRF identity key** is `DocRef` (via `Hash + Eq`). `MemoryFile` and `KnowledgeEntry` can never be equal by type — cross-backend dedup is structurally impossible, which is correct given the store independence invariant.

**FTS5Provider** constructs `DocRef::MemoryFile` from `MemoryHit`. `path` is the absolute path from `DirEntry::path()` — not canonicalized, not symlink-resolved. Stale index entries (file moved/deleted since last reindex) degrade to the raw stored path, not panic.

**RufloProvider** constructs `DocRef::KnowledgeEntry`. It MUST call ruflo in JSON mode (`--json` flag). Table output truncates keys (`knowledge:feed:re...`) — truncated keys are unusable for identity and lookup. Table format is a display artifact; the provider layer never parses it.

**Downstream consumers** pattern-match on `DocRef`. `MemoryFile` → file-backed, can be opened for full content. `KnowledgeEntry` → knowledge extraction, full content in `snippet`. Adding a third backend = new enum variant; the compiler enforces exhaustiveness across all match sites. Enforced in t-2109.

### MCP integration: spawn_blocking, not shell-out

`mcp__brana__recall` calls `HybridProvider::query()` via `tokio::task::spawn_blocking` — same as every other brana-core call in brana-mcp. It does not shell out to the `brana recall` CLI.

The CLI and MCP tool are parallel consumers of the same library function. Neither wraps the other. "Thin wrapper over CLI" applies only to legacy MCP tools where logic lives in the binary rather than brana-core.

### Not L1/L2 cache, not a fallback chain

FTS5 is NOT a cache in front of ruflo. A fallback chain (ruflo → FTS5 on absence) already exists in `knowledge_pipeline.rs`. HybridProvider is additive — parallel query on every call.

## Implementation sequence

1. **t-2095** ✓ — consolidate `which_ruflo()` → `ruflo_memory_search_raw()` canonical
2. **t-2109** — define `SearchProvider` trait + `FTS5Provider` + `RufloProvider` impls, `SearchHit` / `DocRef` identity model, connection-per-query constraint on FTS5Provider, JSON-mode constraint on RufloProvider (S/M, unblocks ADR draft)
3. **ADR update (t-2091)** — add HybridProvider section: sync dispatch rationale, k=20 probe, dedup-dropped rationale, store independence invariant, MCP integration choice, deadline values, non-decisions table. Blocks t-2091 extension. Draft after t-2109 trait shape is concrete.
4. **t-2091 extension** — add `HybridProvider` + `brana recall` CLI command (blocked by t-2109 + ADR update)
5. **t-2096** — wire HybridProvider into skill LOAD steps + session start for proactive enrichment (blocked by t-2091 extension)

**t-2096 constraint:** skill LOAD recall calls must fire in **parallel**, not sequentially. Wall-clock = max(individual calls). If serialized: 5 loads × 2s deadline = 10s blocking on session start.

## Engineering disciplines

- **ADR:** Extends t-2091's SearchProvider ADR. Add HybridProvider section (step 3 above, blocking impl). Non-decisions table must include: k=60 rejected (flat at short list lengths), dedup-before-RRF rejected (destroys dual-signal confirmation, wrong layer for overlap control), shell-out rejected (spawn_blocking already available), Arc<str> on trait rejected (leaks threading concern into abstraction), shared deadline budget rejected (provider independence), source_file: PathBuf on SearchHit rejected (fiction for ruflo entries — use DocRef enum), connection pooling on FTS5Provider rejected (Mutex<Connection> serializes parallel dispatch, defeating purpose), ruflo table output in RufloProvider rejected (key truncation breaks DocRef identity).
- **Tests:** Mock both providers with fixed ranked lists. Verify: RRF math across MIN_CANDIDATE_POOL-depth lists (no dedup), 500ms FTS5 timeout degrades to ruflo-only (not empty), 2s ruflo timeout degrades to FTS5-only, empty ruflo returns FTS5 results unchanged, empty FTS5 returns ruflo results unchanged, top_k=3 with MIN_CANDIDATE_POOL=20 fetches 20 from each provider and truncates output to 3, ruflo budget is consumed from dispatch start not from FTS5 return (worst-case wall-clock ≤ RUFLO_DEADLINE).
- **Docs:** Update `docs/architecture/field-notes/fts5-memory-recall.md` §Recall provider model. Add `brana recall` to command reference when public.
