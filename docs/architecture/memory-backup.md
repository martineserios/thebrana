# Memory Backup and Recovery

Ruflo uses sql.js (in-memory SQLite) for its memory store, flushing to disk every 60 seconds. This makes it vulnerable to data loss on process crash. This doc covers the backup strategy and recovery procedures.

## Backup Layers

### Layer 1: Binary backup (daily)

**Script:** `system/scripts/backup-memory.sh`
**Schedule:** Daily at 07:00 UTC via `backup-memory` scheduler job
**Location:** `~/.swarm/backups/memory_YYYYMMDD.db` (7-day rotation)

Copies `memory.db` directly. Fastest restore path — just copy back.

A corrupt DB is never copied into the backup set. When `PRAGMA integrity_check` fails, the script also appends one line to `~/.swarm/corruption-context.log`: a timestamp, how many `ruflo mcp start` processes were alive at that moment, and their PIDs (t-2805). This is per-event evidence for the concurrency root cause (t-2802); it is not a fix. The log keeps the newest 500 lines and never fails a backup.

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

### Layer 4: Off-site git backup (session close)

**Script:** `~/enter_thebrana/brana-knowledge/backup.sh`
**Trigger:** `/brana:close` Step 10, via `system/skills/_shared/backup-knowledge-invoke.md` → `~/.claude/scripts/backup-knowledge.sh` → `brana-knowledge/backup.sh`
**Location:** private GitHub repo `martineserios/brana-knowledge`, `backup/swarm/` (git-tracked, free tier)

Every session close, a hot `sqlite3 .backup` copy of `~/.swarm/memory.db` is taken locally, then exported to JSON (`memory-entries.json`, `patterns.json` — matches the current RuFlo V3 schema: `memory_entries.content`, `reasoning_patterns`). The JSON exports are committed and pushed to GitHub; also backs up the HNSW/RVF vector artifacts and global + per-project markdown auto-memory (`~/.claude/memory/`, `~/.claude/projects/*/memory/`).

**Important:** the raw `backup/swarm/memory.db` binary itself is **local-only** — it is `.gitignore`'d and never pushed. (Until 2026-09-10 it *was* committed raw to git on every close; 50 versions of the ~130MB file bloated the repo's history to 8.7GB and eventually exceeded GitHub's 100MB single-file limit, silently failing every push. History was rewritten to purge it — see ADR/changelog below.) This means Layer 4's off-site copy is the JSON export only, which does **not** capture everything (no vector embeddings, no causal-graph tables) — a full-fidelity restore of the exact database is not possible from Layer 4 alone. See Layer 5.

### Layer 5: Off-site raw db sync (planned — t-3342)

Free, full-fidelity off-site copy of the raw `~/.swarm/memory.db` via `rclone` → Google Drive (15GB free tier), avoiding GitHub's size limit and LFS costs entirely. `rclone` is installed at `~/.local/bin/rclone`; wiring into `backup.sh` and the one-time interactive Google OAuth setup are tracked in t-3342, not yet complete.

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
| `~/enter_thebrana/brana-knowledge/backup/swarm/memory.db` | Layer 4 local hot-backup copy (NOT git-tracked) |
| `~/enter_thebrana/brana-knowledge/backup/swarm/{memory-entries,patterns}.json` | Layer 4 off-site export (git-tracked, free) |

## Changelog

- 2026-06-08: t-1883 — `sync-state.sh push` now guards `active_epic` against cross-project contamination. See ADR-015 for details.
- 2026-09-10: Fixed `brana-knowledge/backup.sh` — its JSON export queries referenced a pre-V3 schema (`memory_entries.value`, a `patterns` table) and had been silently writing empty `[]` files; corrected to match `memory_entries.content` / `reasoning_patterns`. Also stopped committing the raw `memory.db` binary to git (it had bloated the repo's history to 8.7GB and started exceeding GitHub's 100MB file limit, silently failing every push via a swallowed `2>/dev/null` chain — also fixed to fail loudly). History was rewritten to purge the old blobs. See Layer 4/5 above and t-3342 for the follow-up full-fidelity off-site sync.

## Known Issues

- **Ruflo CLI `memory export`** delegates to non-existent MCP tool `memory_export`. Use `sync-state.sh export` instead.
- **sql.js flush-to-disk** can truncate the DB to 0 bytes on process crash. Binary backup is the mitigation.
- **MCP server caches DB in memory** on startup. Deleting the file requires `memory init --force` to take effect.
- **Layer 4's off-site copy is JSON-only** (no raw db) — a lost machine loses vector embeddings and causal-graph data that aren't in the JSON export, until t-3342 (Layer 5) ships.
