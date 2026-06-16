---
status: accepted
---
# ADR-058: SearchProvider Trait + HybridProvider Recall Architecture

**Status:** Accepted  
**Date:** 2026-06-15  
**Deciders:** Martín Rios  
**Tags:** memory, recall, rust, architecture, search  
**Tasks:** t-2091 (parent), t-2109 (trait impl), t-2124 (this ADR)  
**Spec:** docs/ideas/hybrid-provider-fts5-ruflo-rrf.md (challenger-reviewed x3)

---

## Context

Prior to this ADR, brana had two recall paths that could not be composed:

- **FTS5** (`brana-core/src/memory.rs::search_fts`) — keyword recall over `~/.claude/memory/*.md`, embedded SQLite, zero deps, ruflo-free.
- **ruflo** (`brana-core/src/ruflo.rs::ruflo_memory_search_raw`) — semantic/vector recall over knowledge entries, requires the ruflo binary.

Both paths were called independently (e.g., in `knowledge_pipeline.rs`). There was no abstraction allowing a third caller to query both and merge results. The `brana recall` CLI command and `mcp__brana__recall` MCP tool were unimplementable without a shared interface.

The goal: define a `SearchProvider` trait as a pluggable recall seam, ship two concrete impls, then layer `HybridProvider` on top.

---

## Decision

### 1. SearchProvider trait — sync, `Send + Sync`

```rust
pub trait SearchProvider: Send + Sync {
    fn query(&self, q: &str, top_k: usize) -> Vec<SearchHit>;
}
```

**Sync, not async.** `brana-core` is a synchronous library. Making `SearchProvider` async would require `async_trait`, add `Pin<Box<dyn Future>>` overhead, and force `brana-mcp` to thread async through a library that has no transport concerns. `brana-mcp` already calls all `brana-core` functions via `tokio::task::spawn_blocking`. That pattern is the boundary; the library stays sync.

**`Send + Sync` required.** `HybridProvider` dispatches FTS5 and ruflo calls from `std::thread::spawn`. A provider that is `!Send` cannot be passed across thread boundaries. This constraint is enforced at compile time.

### 2. DocRef — typed document identity

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum DocRef {
    MemoryFile     { path: PathBuf, slug: String, mtype: String, scope: String },
    KnowledgeEntry { key: String, namespace: String },
}
```

`MemoryFile` and `KnowledgeEntry` are structurally disjoint. Two hits from different backends can never compare equal — cross-backend false dedup is impossible at the type level. This is the correct layer for dedup prevention; the ranking layer does not compensate for a missing type invariant.

Adding a third backend = new `DocRef` variant. The compiler enforces exhaustiveness across all match sites.

### 3. FTS5Provider — connection-per-query

`FTS5Provider` holds a `PathBuf` (the db path) and opens a fresh `rusqlite::Connection` on each `query()` call.

`rusqlite::Connection` is `!Send`. Holding it as struct state would make `FTS5Provider: !Send` — a compile error when passed into `thread::spawn`. Connection-per-query is the correct solution. SQLite WAL mode handles concurrent readers. Connection pooling via `Mutex<Connection>` would serialize provider calls and defeat `HybridProvider`'s parallel dispatch.

### 4. RufloProvider — JSON mode only

`RufloProvider` calls `ruflo_memory_search_raw(..., json: true)` unconditionally. Table output from ruflo truncates long keys (`knowledge:feed:re...`), making them unusable as `DocRef::KnowledgeEntry { key }` identities. JSON mode is not optional.

### 5. HybridProvider — parallel dispatch + RRF merge

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

    let start = Instant::now();
    let fts5_results  = rx_fts5.recv_timeout(FTS5_DEADLINE).unwrap_or_default();
    let ruflo_budget  = RUFLO_DEADLINE.saturating_sub(start.elapsed());
    let ruflo_results = rx_ruflo.recv_timeout(ruflo_budget).unwrap_or_default();

    rrf_merge(vec![fts5_results, ruflo_results], K, top_k)
}
```

**`Arc<str>` for query sharing.** One allocation at the dispatch boundary. Each thread receives `Arc::clone` — zero-copy. The `SearchProvider` trait stays `&str` (ergonomic for single-provider callers); the `Arc` is an implementation detail of `HybridProvider`.

**Shared deadline budget.** Both timeouts start from dispatch start, not from when FTS5 returns. Worst-case wall-clock = `RUFLO_DEADLINE` (2s), not `FTS5_DEADLINE + RUFLO_DEADLINE` (2.5s). FTS5 stalling does not consume ruflo's budget.

**Graceful degradation:**
- FTS5 timeout → degrade to ruflo-only results (not empty)
- Ruflo timeout or absent → degrade to FTS5-only results (not empty)
- Both timeout → empty (acceptable edge case)

### 6. RRF with k=20 — no dedup

RRF formula: `score(doc) = sum(1 / (k + rank_in_source_list))` across all provider lists.

**k=20** (not k=60). Calibrated against the actual corpus (10 probe queries, 2026-06-15): FTS5 returns 0–20 results, ruflo returns 3–21 (avg ~11). At k=20 and list length 20, rank spread is ~47%. At k=60, spread collapses to ~24% — functionally flat at these list lengths.

Re-examine k when average ruflo result count exceeds 30 per query.

**No dedup before RRF.** A document appearing in both FTS5 and ruflo receives additive RRF contributions. This is intentional signal — dual-backend confirmation is genuine relevance. The store independence invariant (§7) ensures the stores are independent write paths; overlap in recall is meaningful, not noise.

RRF fetches `MIN_CANDIDATE_POOL` (20) from each provider regardless of `top_k`. Final output is truncated to `top_k` after merge.

### 7. Store independence invariant

FTS5 indexes `~/.claude/memory/*.md` (written by `brana memory write`). Ruflo indexes entries written via `mcp__ruflo__memory_store`. These are independent write paths. brana does not configure ruflo to auto-index `~/.claude/memory/`.

**Two-layer test:**
1. **Config-level:** Assert `ruflo config show` contains no watch path pointing to `~/.claude/memory/` or `~/.claude/projects/*/memory/`. Detects configuration drift.
2. **Read-time smoke:** Assert no ruflo key in `knowledge`/`pattern` namespace matches a `slug` from the FTS5 index. Detects auto-indexing drift that bypasses config-level detection.

### 8. MCP integration — `spawn_blocking`, not shell-out

`mcp__brana__recall` calls `HybridProvider::query()` via `tokio::task::spawn_blocking`. Same pattern as every other `brana-core` call in `brana-mcp`. The CLI (`brana recall`) and MCP tool are parallel consumers of the same library function — neither wraps the other.

### 9. Deadline values

| Provider | Deadline | Rationale |
|----------|----------|-----------|
| FTS5 | 500ms | SQLite is local; 500ms is a conservative ceiling for WAL/lock/I/O stall |
| Ruflo | 2s | `ruflo_memory_search_raw` has a 15s inner timeout; 2s is the acceptable user-facing budget |

Both are independent constants. FTS5 slowness does not reduce ruflo's budget.

**Known limitation:** Timed-out provider threads continue running until their inner timeout expires (up to 15s for ruflo). Rust provides no cancellation API for blocking threads. Peak leaked threads = 2 x (calls that timed out in the last 15s). At current call volumes (<=5 LOAD calls/session, <=1 MCP recall/turn), this is bounded and acceptable. Resolution path: ruflo as a long-running daemon with socket-level timeout. Track under future ADR.

---

## Non-decisions

| Alternative | Rejected because |
|-------------|-----------------|
| `async fn query` on the trait | Forces `async_trait` into `brana-core`; leaks transport concern into a sync library |
| `Arc<str>` on the `SearchProvider` trait | Leaks `HybridProvider`'s threading concern into a single-provider abstraction |
| k=60 (web-scale RRF default) | Score spread collapses to ~24% at list lengths 3–21; rank differentiation is lost |
| Dedup before RRF | Destroys dual-backend confirmation signal; wrong layer — invariant belongs at write path, not ranking |
| Shell-out for MCP integration | `tokio::task::spawn_blocking` already available; shell-out adds process spawn overhead per call |
| `Mutex<Connection>` pool for FTS5 | Serializes FTS5 queries; defeats `HybridProvider` parallel dispatch |
| Ruflo table output in `RufloProvider` | Truncates keys; truncated keys break `DocRef::KnowledgeEntry` identity |
| `source_file: PathBuf` on `SearchHit` | Fiction for `KnowledgeEntry` hits — ruflo entries have no filesystem path; `DocRef` enum represents both correctly |
| Shared deadline budget (total = 2s) | Penalizes ruflo when FTS5 is slow for unrelated reasons; deadlines are independently motivated |
| MemoryStore CRUD abstraction (full trait) | Scope inflation; the seam needed for `brana recall` is over query/recall only, not store/delete |
| L1/L2 fallback chain (FTS5 on miss) | HybridProvider is additive (parallel every call), not a cache; fallback chain already exists in `knowledge_pipeline.rs` for a different purpose |

---

## Consequences

- `SearchProvider` trait is the canonical recall seam. New backends = new struct implementing the trait.
- `HybridProvider` is gated on `FTS5Provider + RufloProvider` being stable (t-2109 complete).
- `brana recall <query>` CLI command and `mcp__brana__recall` MCP tool become implementable.
- t-2096 (proactive memory enrichment at skill LOAD) is blocked on `HybridProvider` shipping. LOAD recall calls must fire in parallel — wall-clock = max(individual calls), not sum.
- Ruflo threshold calibration deferred post-ADR; knowledge namespace scores cap at ~0.50 in current ruflo version (do not hardcode 0.55).

---

## References

- docs/ideas/hybrid-provider-fts5-ruflo-rrf.md — full design spec (challenger-reviewed x3)
- system/cli/rust/crates/brana-core/src/search.rs — SearchProvider trait, FTS5Provider, RufloProvider (t-2109)
- t-2091 — MemoryStore seam (parent task)
- t-2109 — SearchProvider trait + FTS5/Ruflo impls (completed 2026-06-15)
- t-2096 — Proactive memory enrichment at skill LOAD (blocked by HybridProvider)
- ADR-046 — ruflo smart:false LOAD default (related: latency budget informs the 2s ruflo deadline)
