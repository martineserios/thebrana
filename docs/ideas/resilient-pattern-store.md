# Resilient Pattern Store — Hybrid Dual-Write

> Brainstormed 2026-04-01. Status: idea.

## Problem

Ruflo patterns are a write-only sink with no working backup. The 2026-03-31 DB corruption wiped all accumulated patterns. Only 3 real patterns survive (all from 2026-04-01). The backup chain is broken: `patterns-export.json` exports empty arrays, `~/.swarm/backups/` doesn't exist. Meanwhile, Layer 0 (MEMORY.md, git-backed) survived perfectly. The knowledge namespace (1244 entries) is healthy because it's rebuilt from git-native docs — patterns have no equivalent rebuild mechanism.

### Evidence

- DB state: 1254 entries total — 1244 knowledge (healthy), 9 pattern (6 are session context), 1 session
- `patterns-export.json`: exported 2026-03-30 with `{"patterns": [], "decisions": []}` — empty
- `~/.swarm/backups/`: directory doesn't exist — daily binary backup never deployed
- Pattern namespace pollution: session context and reusable patterns share `pattern` namespace
- Session-start hook's ruflo query (`client:$PROJECT`) is keyword search, not semantic — MEMORY.md grep provides equivalent results at current scale

## Proposed solution

Hybrid dual-write architecture. Git (Layer 0 markdown files) is the durable source of truth. Ruflo is the instant semantic search index. Session-end hook writes to both. Ruflo can be rebuilt from git on demand via a pattern indexer.

**Key insight:** This follows the same model as the knowledge namespace. Knowledge lives in git (brana-knowledge dimension docs) and is indexed into ruflo via bulk-index.mjs. Patterns should work the same way — git-native files indexed into ruflo.

### Architecture

```
Session close
  ├─ Layer 0 (git): write pattern as frontmatter .md to ~/.claude/projects/*/memory/
  └─ Ruflo (MCP): memory_store for instant semantic search

Pattern indexer (on demand / weekly)
  ├─ Crawl ~/.claude/projects/*/memory/{feedback,project}_*.md
  ├─ Parse frontmatter → structured pattern
  └─ Bulk-index into ruflo pattern namespace (reuse bulk-index.mjs)

Disaster recovery
  └─ Wipe memory.db → run pattern indexer → 100% recovery from git
```

### Two seeding sources

1. **Curated memory files** (~100 across 8 projects) — already have frontmatter (name, description, type), high-quality, human-maintained
2. **Recovered session payloads** — inline `$CF memory store` JSON from sessions.md, best-effort extraction of patterns lost in 2026-03-31 corruption

## Research findings

- The knowledge pipeline (index-knowledge.sh → bulk-index.mjs) proves git-native → ruflo indexing at scale (1244 entries in 88s)
- 32 curated memory files exist for thebrana alone; estimated ~100 across all projects
- sessions.md contains ~10-15 inline `$CF memory store` payloads with structured JSON
- Semantic search outperforms grep only at 100+ entries — current 3 patterns get no benefit from embeddings
- Session-end hook already writes to both Layer 0 and ruflo — just needs the git write to be structured (frontmatter) instead of prose append
- 3 previously applied ruflo patches were wiped by `npm install -g ruflo` — unknown impact on current functionality

## Risks

| Risk | Mitigation |
|------|-----------|
| Dual-write divergence (git and ruflo drift) | Weekly reconciliation job: export ruflo patterns → diff against git memory files → alert on mismatch |
| Session-end hook complexity increases | Already writes both paths — just needs structured git write (frontmatter) instead of prose append |
| Namespace pollution continues | Separate: session context → `session` namespace, reusable patterns → `pattern` namespace |
| Indexer maintenance burden | Reuse existing bulk-index.mjs with new source dir (memory files instead of dimension docs) |
| Seeding from sessions.md is fragile | Best-effort extraction — accept partial recovery, curated files are the primary seed |

## Next steps

1. **Namespace cleanup** — Move session context entries to `session` namespace. Reserve `pattern` for reusable patterns. Update session-end hook namespace targeting.
2. **Fix broken export** — Debug `sync-state.sh export` empty arrays. Deploy `~/.swarm/backups/` with daily binary rotation cron.
3. **Structure the git write** — Session-end hook writes patterns as frontmatter markdown to `~/.claude/projects/*/memory/` (keeps current `feedback_*`/`project_*` convention).
4. **Build pattern indexer** — Extend index-knowledge.sh + bulk-index.mjs to also crawl `~/.claude/projects/*/memory/*.md`. Reindex on demand via `brana knowledge reindex --patterns`.
5. **Seed from curated memory** — Index existing ~100 memory files across all projects into ruflo `pattern` namespace.
6. **Seed from sessions.md** — Extract inline `$CF memory store` JSON payloads, backfill into ruflo.
7. **Validation test** — Wipe memory.db patterns, run pattern reindexer, verify full recovery.

## Related

- [ruflo-native-integration.md](ruflo-native-integration.md) — P0-P3 ruflo integration phases
- [ADR-026-ruflo-mcp-backbone.md](../architecture/decisions/ADR-026-ruflo-mcp-backbone.md) — MCP tool durability
- [ADR-015-state-consolidation-plugin-first.md](../architecture/decisions/ADR-015-state-consolidation-plugin-first.md) — State sync architecture
