---
depends_on:
  - docs/architecture/decisions/ADR-026-ruflo-mcp-backbone.md
---
# Feature: Resilient Pattern Store

> Status: in-progress (wave 1 complete, wave 2 pending)
> Idea: [docs/ideas/resilient-pattern-store.md](../../ideas/resilient-pattern-store.md)
> Phase: t-815 (Ruflo as Native Backbone) → t-848 (Foundation) + t-849 (Indexer + Seeding)
> ADR: [ADR-026](../decisions/ADR-026-ruflo-mcp-backbone.md) (ruflo MCP backbone)

## Problem

Ruflo patterns are a write-only sink with no working recovery mechanism. The 2026-03-31 DB corruption wiped all accumulated patterns. Evidence:

- Only 3 real patterns survived (all from 2026-04-01)
- `patterns-export.json` exported empty arrays — CLI `memory list` is broken (wiped patches)
- `~/.swarm/backups/` was never created — binary backup never deployed
- Namespace pollution: session context and patterns shared the `pattern` namespace (6/9 entries were session context)
- Layer 0 (MEMORY.md, git-backed) survived perfectly — 32 curated files for thebrana alone

## Solution: Hybrid Dual-Write

Git (Layer 0 markdown files) is the durable source of truth. Ruflo MCP is the instant semantic search index. Session-end hook writes to both. Ruflo can be rebuilt from git on demand.

```
Session close
  ├─ Layer 0 (git): write pattern as frontmatter .md to ~/.claude/projects/*/memory/
  └─ Ruflo (MCP): memory_store for instant semantic search

Pattern indexer (on demand / weekly)
  ├─ Crawl ~/.claude/projects/*/memory/{feedback,project}_*.md
  ├─ Parse frontmatter → structured entries
  └─ Bulk-index into ruflo pattern namespace (reuse bulk-index.mjs)

Disaster recovery
  └─ Wipe memory.db → run pattern indexer → 100% recovery from git
```

## Architecture

### Namespace Split

| Namespace | Contents | Source of truth | Indexed by |
|-----------|----------|----------------|------------|
| `knowledge` | Dimension docs, ADRs, reflections, ideas | Git (brana-knowledge/, thebrana/docs/) | index-knowledge.sh → bulk-index.mjs |
| `pattern` | Reusable patterns (problem/solution pairs) | Git (`~/.claude/projects/*/memory/feedback_*.md`, `project_*.md`) | pattern indexer (new, extends bulk-index.mjs) |
| `session` | Session summaries, session metadata | Git (`brana session write` JSON) + ruflo MCP (searchable mirror) | session-end.sh + close skill step 9b |
| `skills` | Skill frontmatter for routing | Git (system/skills/*/SKILL.md) | index-skills.sh |
| `metrics` | Flywheel metrics per session | Ruflo only (ephemeral, not critical) | session-end.sh |

### Data Flow

**Pattern storage (close skill step 5):**
```
Learning extracted by debrief-analyst
  → MCP memory_store(namespace: "pattern", key: "pattern:{PROJECT}:{slug}")  [instant search]
  → Write frontmatter .md to ~/.claude/projects/*/memory/                   [git durable]
  → MEMORY.md index (if confidence >= 0.8)                                  [always loaded]
```

**Pattern recall (session-start hook):**
```
$CF memory search --query "client:$PROJECT"   [all namespaces, semantic]
  fallback → grep -i "$PROJECT" ~/.claude/projects/*/memory/MEMORY.md  [keyword, always works]
```

**Pattern export (weekly scheduler):**
```
sync-state.sh export
  → Direct SQLite query per namespace (bypasses broken CLI memory list)
  → Writes system/state/patterns-export.json
```

**Pattern recovery (after corruption):**
```
brana knowledge reindex --patterns
  → Crawl ~/.claude/projects/*/memory/*.md
  → Parse frontmatter (name, description, type)
  → bulk-index.mjs → SQLite (same pipeline as knowledge)
```

### Session-End Hook Changes

**Before (wrong):**
```bash
$CF memory store -k "session:$PROJECT:$SESSION_ID" -v "$SUMMARY" --namespace pattern
```

**After (correct):**
```bash
$CF memory store -k "session:$PROJECT:$SESSION_ID" -v "$SUMMARY" --namespace session
```

### Close Skill Step 10 Changes

**Before (wrong):**
```
memory_store(key: "session-meta:...", namespace: "pattern")
```

**After (correct):**
```
memory_store(key: "session-meta:...", namespace: "session")
```

### Export Function Changes

**Before:** Used `$CF memory list` per namespace (broken — returns empty due to wiped patches)

**After:** Direct SQLite query as primary, CLI as fallback:
```bash
sqlite3 "$db_path" "SELECT json_group_array(json_object(...)) FROM memory_entries WHERE namespace='$ns'"
```

Writes per-namespace JSON to temp files, assembles with `jq --slurpfile` to avoid shell variable size limits with large namespaces (knowledge: 1244 entries).

## File Changes

| File | Change | Status |
|------|--------|--------|
| `system/hooks/session-end.sh:164` | `--namespace pattern` → `--namespace session` | ✅ Done |
| `system/skills/close/SKILL.md:459,473` | `namespace: "pattern"` → `namespace: "session"` for session-meta | ✅ Done |
| `system/scripts/sync-state.sh` | SQLite fallback for `ruflo_list_all`, add `session` namespace to export list, restructure `cmd_export` to use temp files | ✅ Done |
| `docs/ideas/resilient-pattern-store.md` | New idea doc | ✅ Done |
| `docs/ideas/ruflo-native-integration.md` | 7 corrections (status, counts, dual-write strategy, failure mode, patches, field note) | ✅ Done |
| `system/skills/close/SKILL.md` | Step 5b: write each pattern as individual frontmatter .md file | ✅ Done (t-852) |
| `system/scripts/index-assumptions.sh` | Add missing `timeout 15` wrapper to `$CF memory store` | ✅ Done (t-852) |
| `system/scripts/index-patterns.sh` | New: Phase 1 shell parser for memory files → JSONL | ✅ Done (t-853) |
| `system/scripts/bulk-index.mjs` | Namespace from JSONL (`s.namespace \|\| 'knowledge'`), namespace-aware orphan cleanup | ✅ Done (t-853) |
| `system/cli/rust/src/cli.rs` | `--patterns` flag on `brana knowledge reindex` | ✅ Done (t-853) |
| `system/cli/rust/src/commands/knowledge.rs` | `cmd_reindex_patterns()` handler | ✅ Done (t-853) |

## Data Migration

| Action | Status |
|--------|--------|
| Move 6 session context entries from `pattern` → `session` namespace | ✅ Done (direct SQLite UPDATE) |
| Verify namespace distribution: 1244 knowledge, 7 session, 3 pattern | ✅ Verified |
| Export 1254 entries to patterns-export.json | ✅ Done (first successful export) |

## Test Plan

- [ ] Verify session-end hook stores to `session` namespace (run close, check DB)
- [ ] Verify close skill step 10 stores session-meta to `session` namespace
- [ ] Verify session-start hook still recalls across all namespaces (no regression)
- [ ] Verify export produces non-empty JSON with all 5 namespaces
- [ ] Verify import round-trip: export → wipe → import → verify counts match
- [ ] (t-856) Wipe pattern namespace → run pattern reindexer → verify 100% recovery
