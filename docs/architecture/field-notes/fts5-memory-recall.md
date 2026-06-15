# FTS5 Memory Recall Seam

## What

`brana memory reindex` + `brana memory search` — embedded SQLite+FTS5 keyword
recall over all project and global memory files. Index lives at
`~/.claude/memory/index.db`. No ruflo dependency, no node.js, no network.

## Why

The previous pattern-indexing pipeline (Phase 1: awk→JSONL, Phase 2:
`node bulk-index.mjs`→ruflo) had three compounding failure points:

1. `awk slug=substr($0,4)` on `patterns.md` read the full markdown body into
   the slug field → malformed JSONL with content in the key, empty value
2. `bulk-index.mjs` crashed on `JSON.parse` of the malformed JSONL (no guard)
3. Deployment drift between tracked and deployed `.mjs` silently dropped fixes

This caused the `reindex-patterns` and related scheduler jobs to fail every run.

## Architecture

```
brana memory reindex
  └── brana-core::memory::reindex_fts()
        └── globs ~/.claude/projects/*/memory/ + ~/.claude/memory/
              └── reindex_fts_dirs() — drops + recreates FTS5 virtual table
                    └── ~/.claude/memory/index.db (SQLite, FTS5)

brana memory search <query>
  └── brana-core::memory::search_fts()
        └── FTS5 MATCH with sanitize_fts_query() (safe tokenizer)
              └── returns MemoryHit {slug, mtype, scope, path, snippet}
```

`rusqlite` uses the `bundled` feature — SQLite compiled from source with FTS5
enabled. Zero system `libsqlite3` dependency.

## Recall provider model

This is the first slice of the pluggable recall seam (t-2091). Two providers:
- **FTS5** (`brana memory search`): keyword, fast, ruflo-free
- **ruflo** (`brana knowledge search`): semantic/vector, requires ruflo running

Same CLI surface, different backends. t-2091 will formalize as a `SearchProvider`
trait once the FTS5 path is proven in production.

## index-patterns.sh

Reduced from ~220 lines (awk+sed parse pipeline) to a 12-line wrapper:

```bash
exec brana memory reindex
```

The scheduler job `reindex-patterns` continues to call this script — no
scheduler config change needed.

## Testability

`reindex_fts_dirs(dirs, db_path)` takes explicit paths — tests use `tempdir()`
without `$HOME` manipulation. Four unit tests in `brana-core::memory::fts_tests`.

## Field Notes

### 2026-06-15: brana-core::ruflo — canonical seam for binary resolution + memory search
t-2095 extracted `resolve_ruflo_binary()` and `ruflo_memory_search_raw()` into `brana-core::ruflo`. Three independent implementations (`knowledge.rs`, `skills.rs`, `knowledge_pipeline.rs`) are now one. The module is the abstraction boundary before the SearchProvider trait (t-2091). Any new ruflo call site must use `ruflo_memory_search_raw()` — not a new shell-out.
Source: t-2095, 2026-06-15

### 2026-06-15: check_semantic_dedup() gained a 15-second timeout as a refactor side effect
Before t-2095, `check_semantic_dedup()` used blocking `.output()` with no timeout — a latent hang risk whenever ruflo stalled. Moving to `ruflo_memory_search_raw()` introduced the 15-second timeout as a side effect. The timeout is intentional in the canonical implementation; the old behavior was a bug, not a design choice.
Source: t-2095, 2026-06-15
