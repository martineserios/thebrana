# Memory Backup and Recovery

Ruflo uses sql.js (in-memory SQLite) for its memory store, flushing to disk every 60 seconds. This makes it vulnerable to data loss on process crash. This doc covers the backup strategy and recovery procedures.

## Backup Layers

### Layer 1: Binary backup (daily)

**Script:** `system/scripts/backup-memory.sh`
**Schedule:** Daily at 07:00 UTC via `backup-memory` scheduler job
**Location:** `~/.swarm/backups/memory_YYYYMMDD.db` (7-day rotation)

Copies `memory.db` directly. Fastest restore path — just copy back.

```bash
# Manual backup
system/scripts/backup-memory.sh

# List available backups
system/scripts/backup-memory.sh --list

# Restore latest
system/scripts/backup-memory.sh --restore

# Restore specific date
system/scripts/backup-memory.sh --restore --date 20260401
```

### Layer 2: JSON export (weekly)

**Script:** `system/scripts/sync-state.sh export`
**Schedule:** Sundays at 08:30 UTC via `export-patterns` scheduler job
**Location:** `system/state/patterns-export.json` (git-tracked)

Exports all namespaces (pattern, decisions, knowledge, skills) via `ruflo memory list` with pagination. Portable and version-controlled.

```bash
# Manual export
system/scripts/sync-state.sh export

# Export + auto-commit to git
system/scripts/sync-state.sh export --auto-commit

# Import from JSON export
system/scripts/sync-state.sh import
```

### Layer 3: Source reindex (on-demand)

Knowledge and skill entries can be fully regenerated from source:

```bash
# Reindex all brana-knowledge dimension docs (~590 sections)
system/scripts/index-knowledge.sh

# Reindex skill frontmatter (25 skills)
system/scripts/index-skills.sh
```

Pattern entries (session closes, learnings, corrections) cannot be regenerated — they accumulate from `/brana:close` and `/brana:retrospective` sessions.

## Recovery Procedures

### Corrupt DB (0-byte file)

1. Delete the corrupt file: `rm ~/.swarm/memory.db`
2. Reinitialize: `ruflo memory init --force` (from `$HOME`)
3. Restore from binary backup: `system/scripts/backup-memory.sh --restore`
4. If no backup: import from JSON: `system/scripts/sync-state.sh import`
5. If no JSON export: reindex from source + accept pattern loss

### New machine setup

```bash
# Pull state from repos
system/scripts/sync-state.sh pull

# Import patterns from JSON
system/scripts/sync-state.sh import

# Reindex knowledge + skills
system/scripts/index-knowledge.sh
system/scripts/index-skills.sh
```

### MCP server caches corrupt state

If the MCP server loaded a corrupt DB at startup, deleting the file isn't enough — the corrupt state is in memory. Fix:

```bash
# Option 1: reinitialize via CLI (resets MCP in-memory state)
cd ~ && ruflo memory init --force

# Option 2: system reset via MCP
# Use mcp__ruflo__system_reset(component: "all", confirm: true)
# Then ruflo memory init --force
```

## Database Paths

| Path | Purpose |
|------|---------|
| `~/.swarm/memory.db` | Current ruflo memory store (primary) |
| `~/.claude-flow/memory.db` | Legacy path (pre-ruflo rename) |
| `~/.swarm/backups/` | Binary backup rotation (7 days) |
| `system/state/patterns-export.json` | JSON export (git-tracked) |
| `.swarm/memory.db` | Project-local swarm DB (legacy, separate) |

## Known Issues

- **Ruflo CLI `memory export`** delegates to non-existent MCP tool `memory_export`. Use `sync-state.sh export` instead.
- **sql.js flush-to-disk** can truncate the DB to 0 bytes on process crash. Binary backup is the mitigation.
- **MCP server caches DB in memory** on startup. Deleting the file requires `memory init --force` to take effect.
