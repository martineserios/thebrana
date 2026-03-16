# ADR-005: AgentDB v3 + RVF as Unified Knowledge Backend

**Date:** 2026-02-24
**Status:** partially activated (2026-02-27) — AgentDB v3 integrated via ruflo v3.5.1 + ControllerRegistry shim. Relational + vector layers active (BM25 hybrid search). Graph layer deferred (Cypher controllers return null). Original kill date (2026-06-24) superseded by successful integration.

## Context

Brana's knowledge artifacts are scattered across multiple locations and formats:

| Location | What | Format | Size |
|----------|------|--------|------|
| `~/.swarm/memory.db` | ruflo memory (178 entries) | SQLite | 852K |
| `~/.swarm/hnsw.index` | Vector index (stale, Feb 10) | Binary HNSW | 560K |
| `~/.swarm/memory.rvf` | RVF vectors (partial, Feb 22) | RVF binary | 69K |
| `~/.swarm/*.json` | Migration artifacts, ID mappings | JSON | 375K |
| `~/.claude/projects/*/memory/` | Per-project auto-memory (9 projects) | Markdown | ~100K |
| `~/.claude/memory/` | Global cross-client knowledge | Markdown | ~25K |
| `~/.claude/scheduler/` | Job state | JSON | ~1K |

Two vector index systems coexist: legacy HNSW (Feb 10, stale) and RVF (Feb 22, partial). Pre-migration backups consume 924K — more than the active database. The `.swarm/` directory has 10 files in 4 formats.

Meanwhile, AgentDB v3.0.0-alpha.3 (Feb 21) unifies what brana currently splits across SQLite + HNSW + markdown:

- **sql.js** — relational layer (key, value, namespace, tags, metadata)
- **RVF native format** — vector layer (embeddings, HNSW indexing, COW branching, temperature tiering, witness chains)
- **Cypher engine** — graph layer (pattern→session→decision relationships)
- **20+ MCP tools** — direct integration with Claude Code
- **ACID persistence** — append-only with crash safety
- **Self-learning pipeline** — SONA retrieval → judgment → distillation → consolidation

RVF is the storage format inside AgentDB v3, not a competing product. The RVF CLI (`rvf-cli` 0.1.0, Rust binary) provides inspection and manipulation tooling for the same `.rvf` files AgentDB produces.

## Decision

### Adopt AgentDB v3 as brana's target knowledge backend

AgentDB v3 replaces the current dual-layer store (SQLite `memory.db` + separate HNSW/RVF index) with a unified backend that natively handles relational data, vector search, and graph queries.

### Phased migration

**Phase 0 — Prepare (now)**
- Clean up stale `.swarm/` artifacts (legacy HNSW, pre-migration backups)
- Install RVF CLI for inspection tooling (`cargo install rvf-cli` — already done)
- Add `memory.rvf` and `rvf-id-mapping.json` to backup pipeline
- Monitor AgentDB v3 releases (alpha.4+)

**Phase 1 — Hybrid (when AgentDB v3 reaches beta or alpha.5+)**
- Install AgentDB v3 alongside existing ruflo memory
- New writes go to AgentDB; reads check both backends
- AgentDB's `LegacyDataBridge` handles schema mapping from existing `memory.db`
- Existing ruflo MCP tools (`memory_store`, `memory_search`) still work
- RVF CLI used for inspection: `rvf status`, `rvf inspect`, `rvf verify-witness`

**Phase 2 — Gradual (after hybrid validation)**
- Background migration: old entries moved to AgentDB on first access
- AgentDB's 20+ MCP tools become primary interface
- Cypher queries enable graph traversals: "patterns from this session", "decisions that led to this outcome"
- COW branching for session snapshots: branch before risky operations, merge or discard
- Temperature tiering: hot patterns at fp16, cold compress to binary (32x smaller)

**Phase 3 — Pure (after full migration)**
- Single `.rvf` container + AgentDB metadata replaces all of `.swarm/`
- Legacy `memory.db` retired
- `backup.sh` exports AgentDB snapshots (RVF branch or JSON)
- `restore.sh` imports from snapshot

### What each layer provides

```
AgentDB v3 (unified backend)
│
├── sql.js (relational)
│   ├── key, value, namespace, tags, metadata
│   ├── WHERE namespace = 'patterns' AND tags LIKE '%session%'
│   └── Replaces: memory.db tables
│
├── RVF (vector + persistence)
│   ├── Embeddings (128-dim, fp16/fp32)
│   ├── HNSW index (progressive: Layer A 70% → Layer C 95% recall)
│   ├── COW branching (session snapshots, 2.6ms for 10K vectors)
│   ├── Witness chain (73-byte SHAKE-256 hash-linked audit)
│   ├── Temperature tiering (hot/warm/cold, automatic via Count-Min Sketch)
│   ├── Crash safety (append-only, two-fsync, no WAL)
│   └── Replaces: hnsw.index + memory.rvf + rvf-id-mapping.json
│
└── Cypher (graph)
    ├── Pattern → caused → outcome
    ├── Session → discovered → pattern
    ├── Decision → supersedes → decision
    └── Replaces: implicit relationships currently stored as tags/text
```

### RVF CLI as inspection tooling

The Rust `rvf-cli` binary is brana's first Rust tool (backlog #36). It provides:

```bash
rvf status ~/.swarm/memory.rvf --json    # Health check
rvf inspect ~/.swarm/memory.rvf           # Segments, lineage, dimensions
rvf verify-witness ~/.swarm/memory.rvf    # Audit chain integrity
rvf derive <file> <snapshot> --type snapshot  # Pre-operation snapshot
```

Not a replacement for AgentDB — a diagnostic companion for the same file format.

### Artifact management target state

```
Phase 0 (now):                    Phase 3 (target):
~/.swarm/                         ~/.swarm/
├── memory.db        852K         ├── knowledge.rvf    (single file)
├── memory.rvf        69K         └── schema.sql       (reference)
├── hnsw.index       560K  ←DEL
├── hnsw.metadata     4K   ←DEL
├── memory.db.bak   708K   ←DEL   ~/.claude/memory/    (unchanged)
├── export-pre.json  124K  ←DEL   ~/.claude/projects/  (unchanged)
├── with-embed.json   92K  ←DEL
├── ingest-128.json  284K  ←KEEP until Phase 3
├── id-mapping.json    8K  ←KEEP until Phase 3
└── schema.sql        12K
```

Markdown layers (`MEMORY.md`, session handoffs, global memory) remain as-is. They serve a different purpose: human-readable context loaded into Claude's prompt. AgentDB handles machine-searchable knowledge; markdown handles prompt engineering.

## RVF technical assessment (from hands-on testing)

RVF CLI v0.1.0 is installed at `~/.cargo/bin/rvf`. Tested against `~/.swarm/memory.rvf` (132 vectors, 128-dim, 1 VEC segment).

### Verified

- Create, ingest, query, delete, compact, derive, filter, status, inspect
- COW derive produces 162-byte header-only children (zero-copy)
- Crash-safe append-only format (SFVR magic, 64-byte segment headers)
- 26 segment types covering vectors, indexing, COW, crypto, execution

### Known alpha limitations

| Issue | Impact | Mitigation |
|-------|--------|------------|
| No export command | Can't extract vectors from .rvf to JSON | Keep `rvf-ingest-128.json` as rebuild source |
| Derived files don't query parents | COW children are isolated, not transparent views | Wait for fix; snapshots still useful as backups |
| Freeze advisory only | Writes succeed after freeze | Don't rely on freeze for immutability |
| CLI negative float bug | `--vector "-0.1,..."` parsed as flags | Use `--vector="..."` (equals syntax) |

### RVF format strengths (driving adoption)

| Feature | Spec | Benefit for brana |
|---------|------|-------------------|
| Single-file container | 26 segment types in one `.rvf` | Replaces 5+ scattered files |
| Append-only + two-fsync | No WAL, no corruption | Safe for concurrent hook/scheduler access |
| COW branching | 2.6ms for 10K vectors | Session snapshots before risky operations |
| Witness chain | 73 bytes/event, SHAKE-256 | Audit trail for pattern mutations |
| Temperature tiering | Hot fp16, cold binary 32x | Knowledge aging — recent patterns fast, old ones compressed |
| Progressive indexing | Layer A (70%), B (85%), C (95%) | Cold boot <5ms, full recall when needed |
| KERNEL/WASM segments | Bootable Linux in 125ms | Future: knowledge base deploys as microservice |

## Alternatives considered

### Stay on SQLite + separate HNSW
Pro: working, simple. Con: two stale index systems, growing artifact scatter, no path to graph queries or session branching. The current architecture doesn't evolve — it just accumulates.

### RVF standalone (without AgentDB)
Pro: simpler, one dependency. Con: RVF stores vectors, not relational data. Brana needs namespace queries, tag filtering, date ranges — all of which require the sql.js layer that AgentDB provides. Using RVF alone means maintaining a dual-store (SQLite + RVF) indefinitely.

### Build custom integration
Pro: exact fit. Con: reimplements what AgentDB v3 already ships. AgentDB's phased migration (hybrid → gradual → pure) is exactly the adoption pattern we'd design anyway. No point building it from scratch.

### Wait for everything
Pro: zero risk. Con: artifact scatter worsens, stale HNSW persists, RVF file isn't in backup pipeline, no progress on backlog #36 or #57. Phase 0 cleanup has zero risk and immediate benefit.

## Consequences

### Becomes easier
- Single knowledge backend (AgentDB v3) replaces SQLite + HNSW + RVF scatter
- Graph queries on pattern relationships (Cypher) — currently impossible
- Session snapshots via COW branching — currently manual
- Audit trail via witness chain — currently no mutation tracking
- Temperature-based knowledge aging — currently all patterns equal
- Phased migration: no big-bang, hybrid coexistence with existing ruflo
- Rust enters the stack via pre-built binary (zero build cost)

### Becomes harder
- Dependency on AgentDB v3 stability (alpha software, ruvnet is sole maintainer)
- Phase 1-2 requires hybrid mode: two backends active simultaneously
- Cypher query syntax is a new skill to learn
- If AgentDB v3 stalls, we're left with a cleaner Phase 0 state but no unified backend

### Phase 0 risk: none
Cleanup + backup updates + monitoring. Fully reversible. No behavior change.

### New dependencies
- `rvf-cli` 0.1.0 (Rust, installed via cargo)
- `agentdb` npm package (Phase 1+, when stable)
- Monitor: AgentDB releases, RVF CLI updates, ruflo integration (Issue #829)
