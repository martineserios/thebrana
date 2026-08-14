---
title: Local Vector Recall — own retrieval, drop the index
status: built
created: 2026-08-03
tasks: [t-2620, t-2619, t-2616]
supersedes: []
---

# Local Vector Recall

> Take back storage and search for the knowledge base. Keep ruflo only for the
> one thing it does reliably: generating embeddings.

## Problem

Knowledge is captured, extracted, and persisted correctly — and is then
unreachable by any topic query. A link sent via Telegram is fetched, summarised,
embedded, and stored, and no amount of searching will surface it again.

Measured 2026-08-03 against the live store:

| Fact | Value |
|---|---|
| Rows in `memory_entries` | 4,441 |
| Rows carrying a valid 384-dim embedding | 4,441 |
| Vectors in the HNSW index | **2** |
| `knowledge:url:` entries ever returned by semantic search | **0** |

Three primitives in the same layer fail, all silently:

1. `ruflo memory search` — retrieves against an index holding 2 vectors, so it
   falls back to a partial brute-force scan that has never returned a captured
   link.
2. `ruflo embeddings index -a build` — prints `Index build complete`, exits 0,
   leaves the vector count at 2. It does not read `memory_entries`.
3. `ruflo memory delete` — reports success, deletes nothing (verified: probe
   rows survived and had to be removed with SQL).

A fourth defect sits underneath: `ruflo-mcp.sh` rotates `~/.swarm/memory.db` on
every MCP launch, discarding databases that pass `integrity_check` standalone
and restoring backups underneath stale `-wal`/`-shm` sidecars, which
re-corrupts them immediately (t-2619).

### Isolation probe

The failure is not specific to link keys. Storing a fresh entry with a unique
nonsense phrase via `ruflo memory store` — the exact call `drain-links` makes —
then searching that exact phrase does not return it. Repeating with the same
value under a `knowledge:feature:` key also does not return it. Exact-key
`ruflo memory retrieve` **does** work.

So: writes land, keys resolve, embeddings are correct, and semantic retrieval
is blind.

## The insight

The data is fine. Only the layer on top is broken.

Brute-force cosine over the *same rows ruflo cannot find*, measured on the live
DB:

```
4,441 vectors · 384 dims
  pure Python loop ............ 91 ms
  numpy dot product ...........  2.34 ms
  top hit = the query itself ... score 1.0
```

A 2.34 ms exact scan returns the correct answer where a purpose-built vector
index returns nothing. That is the entire justification for this design.

## Solution

Keep the parts that work. Replace storage and search. Add the recall hook.

```
KEEP
  Telegram → queue → task → process-url → extract insight
  ONNX embedding generation (all-MiniLM-L6-v2, 384d)   ← ruflo, works fine
            │
            ▼
REPLACE
  ~/.claude/memory/knowledge.db      ← brana-owned, NOT ~/.swarm/
    key · content · tags · source · created_at · vec BLOB(1536B)
            │
            ▼
  brute-force cosine                 ← no HNSW, no index to desync
            │
            ▼
  brana recall = FTS5 (already works) ⊕ vectors, RRF-merged
            │
            ▼
ADD
  UserPromptSubmit hook → top 3 above threshold → additionalContext
```

### 1. Our own table

`~/.claude/memory/knowledge.db`, beside the FTS5 index that already works.

`~/.swarm/memory.db` is rotated and corrupted daily by a script that runs on
every Claude Code session start. Anything we build on it inherits that. A
brana-owned file is not touched by ruflo at all.

Vectors stored as a `BLOB` of 384 little-endian `f32` (1,536 bytes), not the
current JSON-array text. The JSON parse is the only slow part of the measurement
above (808 ms for the full set); a BLOB is memory-mappable and parse-free.

### 2. No index

Brute force every query. At 4,441 vectors that is ~2 ms in numpy and under 1 ms
in Rust. HNSW is an optimisation for millions of vectors; at this scale it buys
nothing measurable and is exactly the component that is broken.

Total vector payload at current scale: 4,441 × 384 × 4 B = **6.8 MB**. It fits
in cache.

Revisit at ~100k entries, where a full scan reaches roughly 50 ms. That is the
trigger to add an index — not before.

### 3. Retrieval through `brana recall`

`brana recall` already implements the hard part: an FTS5 provider that works, a
`HybridProvider`, and RRF merging. The change is swapping `RufloProvider` for a
local `VectorProvider` over the new table.

Result: one command, lexical + semantic, both ours, no MCP dependency.

### 4. The auto-recall hook

`UserPromptSubmit` → `brana recall --json "$PROMPT" --top 3` → emit hits as
`additionalContext`.

Guards, so this stays useful rather than noisy:
- score threshold — inject nothing rather than something irrelevant
- hard token cap on injected context
- skip slash commands and very short prompts
- fail open: a hook error must never block the prompt

## Why not fix ruflo

| | Fix ruflo | This design |
|---|---|---|
| Ownership | upstream, not ours | ours, testable |
| Today's failures | 3 primitives + daily corruption | none of that surface |
| Failure mode | **silent success** | no index to desync |
| Keeps what works | — | yes, embedding generation |

Every failure found was silent — success reported, nothing done. That is the
property that makes the layer untrustworthy, and it is not fixed by patching one
of its three broken calls.

**Honest counter-argument:** this is more code we own and maintain. Accepted:
the replacement is small (a table, a cosine function, a provider swap), fully
testable, and removes a dependency that reports success while doing nothing.

## Non-goals

- Replacing ruflo's embedding generation — it works, keep it.
- Migrating other ruflo namespaces (`pattern`, `session`, `metrics`).
- Fixing the killed reindex (t-2616) or LinkedIn fetch reliability. Independent.

## Migration

One-time copy from `memory_entries`: key, content, tags, created_at, and the
embedding converted from JSON text to `f32` BLOB. The data already exists and is
provably correct — the 1.0 self-match confirms embeddings and content agree.

No re-fetch, no re-embed, no network.

## Sequencing

1. **t-2619 first.** Stop the daily rotation loss. Small. Everything else is
   pointless while the store rolls back daily.
2. **This spec.** Table, migration, brute-force search behind `brana recall`.
3. **The hook.** Only worth building once 1 and 2 land.

> **Sequencing revision (2026-08-10, t-2620):** t-2619's own audit found its
> "fixes the daily loop" diagnosis unsupported (reclassified as reaction
> hardening; root cause moved to t-2626), so item 1 stopped being a
> precondition — the brana-owned store makes rotation irrelevant to retrieval.
> Item 2 shipped without waiting.

## Implementation notes (t-2620, 2026-08-10)

- `brana-core::vector` — `KnowledgeStore` (schema as designed, f32 LE BLOB),
  `cosine`, `VectorProvider` (fail-open, threshold-gated), `Embedder` seam with
  `RufloEmbedder` (`ruflo embeddings generate -t <q> -o json`), and
  `migrate_from_memory_entries`.
- **Migration became a salvage union**, not the single-source copy assumed
  here: by build time the live DB had rolled back again (122 knowledge rows).
  The union of `memory.db.corrupt-2026-08-03` (passes `integrity_check`; 3,801
  embedded rows) and the live DB migrated **3,922 entries**, dedup by key,
  newest `updated_at` wins.
- `brana knowledge vector-sync [--source …] [--dest …] [--json]` — idempotent
  re-sync; scheduler job `knowledge-vector-sync` runs 20min after each
  `drain-links` pass.
- Both `brana recall` (CLI) and the `recall` MCP tool now build
  `HybridProvider(FTS5, VectorProvider)`; `RufloProvider` remains in
  `search.rs` but has no production call site.
- Verified live: `brana recall "python web scraping framework"` returns the
  `knowledge:url:…python-framework-scrapes…` entry captured via Telegram —
  the first `knowledge:url` hit semantic search has ever returned. 0.7s total
  (ONNX embed shell-out dominates; the scan is sub-ms).
- The auto-recall hook (item 3) remains open — tracked separately.

## Acceptance criteria

- AC: an entry written by the link pipeline is retrievable by topic query within one cycle
- AC: `brana recall` returns knowledge entries, not only memory files
- AC: retrieval path has zero dependency on ruflo's index, store, or delete
- AC: search latency under 50 ms at 10k entries
- AC: migration preserves every existing entry with its embedding
- AC: `UserPromptSubmit` hook injects recalled context, and fails open on error
