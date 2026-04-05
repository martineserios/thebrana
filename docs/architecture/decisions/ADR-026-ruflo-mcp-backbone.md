---
depends_on:
  - docs/architecture/decisions/ADR-005-agentdb-v3-unified-knowledge-backend.md
supersedes:
  - docs/architecture/decisions/ADR-005-agentdb-v3-unified-knowledge-backend.md
---

# ADR-026: Ruflo MCP as Backbone, CLI as Fallback

**Date:** 2026-04-01
**Status:** accepted
**Tasks:** ruflo integration session (2026-04-01)

## Context

Brana treated ruflo as an optional CLI tool since ADR-005. Of ruflo's 218 MCP tools, only 6 were actively used. Investigation on 2026-04-01 revealed three compounding problems:

1. **Split database paths.** The MCP server pointed to one SQLite DB while CLI invocations (via `$CF` in hooks) used a CWD-relative `.swarm/memory.db` — effectively two separate memory stores that never saw each other's data.

2. **Ephemeral stubs masquerading as durable tools.** `hierarchical-store` and `hierarchical-recall` are backed by an in-memory `Map` stub in agentdb's `index.js` — data is lost on every ruflo restart. They are not exported from the agentdb module and cannot be fixed without upstream changes.

3. **Underutilization.** With 15 agentdb controllers active and verified, brana was leaving durable infrastructure (HNSW vector search, SQLite persistence, BM25 text search) on the table by routing everything through 4 CLI calls.

A store-kill-recall test confirmed that `memory_store` / `memory_search` survive process restarts (SQLite + HNSW backed). This made the backbone decision clear.

## Decision

**MCP is the backbone for skills. CLI is the backbone for hooks. Rust CLI stays local-only.**

### 1. Skills Call MCP Directly

All skill SKILL.md files that need ruflo now list specific `mcp__ruflo__*` tools in their `allowed-tools` frontmatter. Skills call these tools directly — no CLI intermediary.

### 2. Hooks Use CLI (`$CF`)

Shell hooks cannot call MCP tools (no stdio access from a hook script). Hooks continue using `$CF` (resolved by `cf-env.sh`) for basic memory operations. The CWD bug is fixed: all hook `$CF` calls now run from `$HOME` via `cd "$HOME" &&` to ensure the correct DB path.

`cf-env.sh` gains a `cf_run()` wrapper function that handles the `cd "$HOME"` automatically.

### 3. Rust CLI Stays Local-Only

The `brana` Rust binary handles backlog, transcription, files, feeds, inbox, and session management. These are local operations that do not need ruflo. No ruflo dependency is added to the Rust CLI.

### 4. Graceful Degradation Chain

When ruflo MCP is unavailable:

```
MCP tools → CLI ($CF) fallback → MEMORY.md (native auto memory)
```

Skills detect MCP availability and fall back to CLI calls. If CLI is also unavailable, patterns are written to `~/.claude/projects/*/memory/` as markdown — the same mechanism brana used before ruflo existed.

## Tool Durability Classification

Based on empirical testing (store-kill-recall, response inspection, source code audit):

### Durable (SQLite/HNSW backed, survive restart)

| Tool | Backend | Notes |
|------|---------|-------|
| `memory_store` | SQLite + HNSW embeddings | Primary pattern store |
| `memory_search` | SQLite + HNSW + BM25 | Primary recall path, 26ms typical |
| `hooks_intelligence_pattern-search` | HNSW + BM25 | Durable, fast |
| `embeddings_compare` | ONNX model (all-MiniLM-L6-v2) | Stateless, always available |
| `agentdb_session-start` / `session-end` | Bridge fallback | Session metadata persisted |
| `agentdb_causal-edge` | Bridge fallback | Relationship edges persisted |
| `agentdb_feedback` | Bridge fallback | Feedback entries persisted |

### Transient (in-memory, best-effort)

| Tool | Backend | Notes |
|------|---------|-------|
| `hive-mind_*` | In-memory mesh | Lost on restart; useful for intra-session coordination |
| `claims_*` | In-memory map | Lost on restart; useful for intra-session task claiming |
| `agent_spawn` / `agent_list` | Process table | Ephemeral by nature |
| `coordination_orchestrate` | In-memory | Ephemeral by nature |

### Broken (do not use)

| Tool | Failure Mode | Upstream Issue |
|------|-------------|----------------|
| `hierarchical-store` / `hierarchical-recall` | In-memory Map stub, NOT exported from agentdb index.js | ruvnet/ruflo#1492 |
| `context-synthesize` | Stub, returns empty | ruvnet/ruflo#1492 |
| `agentdb_batch` | Writes to `episodes` table, not `memory_entries` — unusable for knowledge indexing. Workaround: direct SQLite bulk insert via `bulk-index.mjs` using ruflo's own deps. | ruvnet/ruflo#1492 |
| `agentdb_semantic-route` | Non-functional | ruvnet/ruflo#1492 |

### Degraded

| Tool | Issue | Notes |
|------|-------|-------|
| `hooks_intelligence_pattern-store` | Bridge-fallback path, not HNSW-indexed | Stored but not vector-searchable until reindex |

## Skill Integration Changes

| Skill | Change |
|-------|--------|
| **close** | 3 additive MCP calls: session mirror (`agentdb_session-end`), hive-mind announce (`hive-mind_broadcast`), claims release (`claims_release`) |
| **sitrep** | Pattern-search as Source 6 (`hooks_intelligence_pattern-search`), hive-mind as Source 7 (`hive-mind_memory`) |
| **research** | Phase 0 uses `memory_search(namespace: "all")` instead of 4 separate CLI calls |
| **build** | Announces to hive-mind on start; backlog start/done claims tasks |
| **index-knowledge.sh** | Upgraded to 7 doc categories with tier tags |
| **index-skills.sh** | New script for skill frontmatter indexing |
| **session-start hook** | Runs `index-skills.sh --changed` in background |

## Alternatives Considered

### A. CLI-only (status quo)

Keep routing everything through `$CF` CLI calls. Rejected because:
- CWD-relative DB path is fragile and caused the split-DB bug
- CLI subprocess overhead on every memory operation
- Cannot leverage MCP's richer tool surface (embeddings, pattern-search, hive-mind)

### B. Full MCP-only (no CLI fallback)

Remove all CLI usage and require MCP for everything. Rejected because:
- Shell hooks cannot call MCP tools (no stdio transport)
- Graceful degradation requires a non-MCP fallback path
- Would break offline/no-ruflo sessions entirely

### C. Custom MCP wrapper

Build a brana-specific MCP server that proxies to ruflo with correct DB paths. Rejected because:
- Adds a maintenance surface and process to manage
- The root cause (wrong DB path) is fixable with `cd "$HOME"`
- No capability gain over direct MCP calls

## Consequences

- **All skill SKILL.md files updated** with explicit `mcp__ruflo__*` tools in allowed-tools where ruflo integration exists.
- **Hook reliability improved.** `cf-env.sh` `cf_run()` wrapper eliminates the CWD-relative DB path bug.
- **Knowledge indexing expanded.** `index-knowledge.sh` now handles 7 doc categories. `index-skills.sh` indexes skill frontmatter for semantic search.
- **Upstream dependency acknowledged.** 4 broken tools tracked in ruvnet/ruflo#1492. Brana works around them but cannot fix them — they require upstream changes to agentdb's module exports and controller implementations.
- **`namespace: "all"` convention adopted.** Cross-namespace search via `memory_search(namespace: "all")` is undocumented but verified working. Skills use this for broad recall instead of namespace-specific queries.
- **`pattern` (singular) namespace convention.** Brana uses `pattern` to match ruflo's internal convention. 476 entries migrated on 2026-04-01.
