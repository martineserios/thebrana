# Scripts Reference

Helper scripts that support hooks, skills, and maintenance workflows. Located in `system/scripts/`.

## cf-env.sh

| Field | Value |
|-------|-------|
| **Purpose** | Locate the ruflo binary |
| **Usage** | `source cf-env.sh` -- sets `$CF` variable |
| **Dependencies** | None (graceful if ruflo is absent) |

Search order:
1. nvm global install: `$HOME/.nvm/versions/node/*/bin/claude-flow`
2. PATH lookup: `command -v ruflo`
3. npx fallback: `npx ruflo`

Exports `$CF` (empty string if not found). A duplicate copy exists at `system/hooks/lib/cf-env.sh` for the plugin hooks to use without depending on bootstrap installation.

---

## memory-store.sh

| Field | Value |
|-------|-------|
| **Purpose** | Store a key-value pair in ruflo memory with auto-fallback |
| **Usage** | `memory-store.sh -k KEY -v VALUE [-n NAMESPACE] [-t TAGS]` |
| **Dependencies** | `cf-env.sh` (sourced automatically) |

Attempts to store via `ruflo memory store`. If ruflo is unavailable or the store fails, falls back to appending the entry to the first project `MEMORY.md` file found in `~/.claude/projects/*/memory/`.

### Arguments

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `-k` | Yes | -- | Storage key |
| `-v` | Yes | -- | Value to store |
| `-n` | No | `patterns` | Memory namespace |
| `-t` | No | `""` | Comma-separated tags |

---

## index-knowledge.sh

| Field | Value |
|-------|-------|
| **Purpose** | Index brana-knowledge dimension docs into ruflo memory for semantic search |
| **Usage** | `index-knowledge.sh` (all), `index-knowledge.sh file.md` (specific), `index-knowledge.sh --changed` (git-changed only) |
| **Dependencies** | Node.js, `bulk-index.mjs`, ruflo's `better-sqlite3` + `@xenova/transformers` |
| **Status** | Active — canonical location is `system/scripts/index-knowledge.sh` |

Two-phase pipeline:

1. **Phase 1 (shell):** Parses markdown by `##` headings, classifies tier/type from file path, outputs JSONL to a temp file
2. **Phase 2 (Node.js):** `bulk-index.mjs` reads JSONL, batch-generates 384-dim ONNX embeddings, writes directly to SQLite (`~/.swarm/memory.db`)

Each section becomes a memory entry:

- **Key:** `knowledge:{type}:{doc-slug}:{section-slug}`
- **Namespace:** `knowledge`
- **Tags:** `[source:{repo}, type:{type}, doc:{filename}, tier:{tier}]` (JSON array)
- **Value:** Section content, truncated to 2000 characters

Falls back to legacy per-section `ruflo memory store` if `bulk-index.mjs` is missing.

### Modes

| Mode | Trigger | Use case |
|------|---------|----------|
| `index-knowledge.sh` | No args | Full reindex of all 7 categories + orphan cleanup |
| `index-knowledge.sh file1.md` | Filename args | Index specific files |
| `index-knowledge.sh --changed` | `--changed` flag | Index only git-changed files (for post-commit hook) |

### Doc Categories (7)

| Directory | Type | Tier |
|-----------|------|------|
| `brana-knowledge/dimensions/` | dimension | semantic |
| `docs/architecture/decisions/` | decision | semantic |
| `docs/architecture/features/` | feature | episodic |
| `docs/architecture/` | architecture | semantic |
| `docs/reflections/` | reflection | semantic |
| `docs/ideas/` | idea | working |
| `docs/research/` | research | episodic |

---

## bulk-index.mjs

| Field | Value |
|-------|-------|
| **Purpose** | Batch embed + store knowledge sections directly to SQLite (Phase 2 of indexing pipeline) |
| **Usage** | `node bulk-index.mjs [--cleanup] [path/to/sections.jsonl]` |
| **Dependencies** | ruflo's `better-sqlite3`, `@xenova/transformers` (resolved dynamically) |
| **Status** | Active — canonical location is `system/scripts/bulk-index.mjs` |

Reads JSONL (one entry per line with `key`, `value`, `tags`), generates 384-dim embeddings in batches of 20, writes to `memory_entries` table via SQLite transactions. ~100x faster than per-section CLI calls.

Dynamically resolves ruflo's `node_modules` via 3 strategies: `npm root -g`, `process.execPath` prefix, `which ruflo` symlink.

| Flag | Default | Description |
|------|---------|-------------|
| `--cleanup` | off | Remove orphan knowledge entries not in this run |
| `[path]` | `/tmp/knowledge-sections.jsonl` | JSONL file to read |

### CLI wrapper

| Command | Effect |
|---------|--------|
| `brana knowledge reindex` | Full reindex (all 7 categories + orphan cleanup) |
| `brana knowledge reindex --changed` | Git-changed files only |
| `brana knowledge reindex file.md` | Specific file(s) |
| `brana knowledge status` | Show entry count + last indexed timestamp |

---

## generate-index.sh

| Field | Value |
|-------|-------|
| **Purpose** | Generate `dimensions/INDEX.md` from dimension doc headers |
| **Usage** | `generate-index.sh [knowledge-dir]` |
| **Dependencies** | None |
| **Status** | Active — canonical location is `system/scripts/generate-index.sh` |

Scans all `.md` files in the dimensions directory (excluding INDEX.md itself). For each doc, extracts:
- Title from first `#` line
- Count of `##` sections
- File size (formatted as B/KB/MB)

Outputs a markdown table to `INDEX.md` with total doc count and generation date.

Default knowledge directory: `~/enter_thebrana/brana-knowledge`.

---

## skill-graph.sh

| Field | Value |
|-------|-------|
| **Purpose** | Generate a Mermaid flowchart of skill groups and dependencies |
| **Usage** | `skill-graph.sh [skills-dir]` |
| **Dependencies** | Python 3, PyYAML |

Reads YAML frontmatter from all `SKILL.md` files in the skills directory. Extracts `group` and `depends_on` fields. Outputs a Mermaid `flowchart LR` diagram with:
- Subgraphs per group
- Dependency arrows between skills

Default skills directory: `../skills` relative to the script.

---

## brana graph build (spec graph)

| Field | Value |
|-------|-------|
| **Purpose** | Generate a JSON dependency graph of all spec documents |
| **Usage** | `brana graph build [--output PATH]` |
| **Dependencies** | Rust CLI (`brana` binary) |

Parses all markdown files in `docs/`, including subdirectories `dimensions/`, `research/`, `guide/`, and `architecture/` (symlinks followed explicitly). Extracts cross-reference links, `system/` file mentions, and typed relationship edges. Replaces the former `system/scripts/spec_graph.py`.

### Subcommands

See `brana graph --help` for full subcommand list: `build`, `orphans`, `query`, `path`, `stats`, `validate`.

### Arguments (build)

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--output` / `-o` | No | `docs/spec-graph.json` | Output file path |

### Output

JSON with three top-level keys:

| Key | Description |
|-----|-------------|
| `_meta` | Stats: `node_count`, `edge_count`, `impl_ref_count`, `orphan_count`, `typed_edge_count` |
| `nodes` | Per-doc: `references`, `referenced_by`, `impl_files`, `guide_files`, `arch_files`, `ref_files` |
| `typed_edges` | Relationship edges: `{from, to, type}` where type is assumes/implements/informs/enriches/supersedes |

See [spec-graph workflow guide](../guide/workflows/spec-graph.md) for full schema and query examples.

---

## decisions.py

| Field | Value |
|-------|-------|
| **Purpose** | Manage the JSONL decision log — log entries, read/filter, archive old files |
| **Usage** | `uv run python3 system/scripts/decisions.py <subcommand> [args]` |
| **Dependencies** | Python 3 (stdlib only) |

Append-only JSONL decision log stored in `system/state/decisions/`.

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `log` | Append one entry to the current session's file |
| `read` | Read and filter entries across all active files |
| `archive` | Move old files to `archive/` subdirectory |

### Arguments (log)

| Positional | Description |
|-----------|-------------|
| `agent` | Agent name (e.g., main, scout, challenger) |
| `type` | Entry type: decision, finding, concern, action, error, cost |
| `content` | Entry text |

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--severity` | No | -- | HIGH, MEDIUM, or LOW |
| `--refs` | No | -- | Comma-separated references |
| `--target` | No | -- | Entry this responds to |

### Arguments (read)

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--last` | No | all | Return only last N entries |
| `--type` | No | -- | Filter by entry type |
| `--agent` | No | -- | Filter by agent name |
| `--severity` | No | -- | Filter by severity |
| `--json` | No | false | Output raw JSON lines |

### Arguments (archive)

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--days` | No | 30 | Age threshold in days |
| `--dry-run` | No | false | Preview without moving |

### Environment variables

| Variable | Description |
|----------|-------------|
| `BRANA_SESSION_ID` | Session identifier for file naming |
| `BRANA_DECISIONS_DIR` | Override state directory path (testing) |

---

## generate-reference.py

| Field | Value |
|-------|-------|
| **Purpose** | Generate `docs/reference/` files deterministically from source metadata |
| **Usage** | `uv run python3 system/scripts/generate-reference.py [--output-dir PATH] [--check]` |
| **Dependencies** | Python 3 (stdlib only) |

Reads YAML frontmatter from `system/skills/*/SKILL.md`, `system/agents/*.md`, `system/hooks/hooks.json` + `*.sh`, `system/rules/*.md`, and `system/commands/`. Generates five reference files: `skills.md`, `agents.md`, `hooks.md`, `rules.md`, `commands.md`.

### Arguments

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--output-dir` | No | `docs/reference/` | Output directory |
| `--check` | No | false | Exit 1 if any file would change (CI gate) |

---

## cc-changelog-check.sh

| Field | Value |
|-------|-------|
| **Purpose** | Detect CC version changes and write a review report |
| **Usage** | `./system/scripts/cc-changelog-check.sh` (or via scheduler weekly) |
| **Dependencies** | npm (for `npm view @anthropic-ai/claude-code version`), curl |

Checks the npm registry for the latest `@anthropic-ai/claude-code` version. Compares against cached version in `~/.claude/cc-version-cache`. If changed, writes `~/.claude/cc-changelog-report.md` with old/new version and action steps. Session-start hook surfaces the report.

Scheduled weekly (Mon 10:00) via `~/.claude/scheduler/scheduler.json` → `cc-changelog-review`.

---

## gh-sync.sh

| Field | Value |
|-------|-------|
| **Purpose** | Sync tasks.json with GitHub Issues via `gh` CLI |
| **Usage** | `gh-sync.sh <subcommand> [args]` |
| **Dependencies** | `gh` CLI, `jq` |

Subcommands: `create <task-id> <tasks-json>`, `close <issue-number>`, `update <task-id> <tasks-json>`, `pull-context <issue-number>`. Used by `task-completed.sh` (PostToolUse hook) and by `brana backlog sync` (Rust CLI).

---

## index-assumptions.sh

| Field | Value |
|-------|-------|
| **Purpose** | Index assumptions and field notes from docs into ruflo memory |
| **Usage** | `index-assumptions.sh` |
| **Dependencies** | ruflo with embeddings |

Creates/populates three namespaces (ADR-021): `assumptions` (tracked claims from ADR frontmatter), `field-notes` (learnings from doc Field Notes sections), `decisions` (ADR summaries).

---

## index-patterns.sh

| Field | Value |
|-------|-------|
| **Purpose** | Index pattern files (feedback_*.md, project_*.md) from all project memory dirs into ruflo memory for semantic search |
| **Usage** | `index-patterns.sh` (all), `index-patterns.sh --project thebrana` (specific project), `index-patterns.sh file1.md` (specific files) |
| **Dependencies** | Node.js, `bulk-index.mjs`, ruflo's `better-sqlite3` + `@xenova/transformers` |
| **Status** | Active — canonical location is `system/scripts/index-patterns.sh` |

Two-phase pipeline (reuses `bulk-index.mjs`):

1. **Phase 1 (shell):** Parses frontmatter + body from `~/.claude/projects/*/memory/` files, outputs JSONL
2. **Phase 2 (Node.js):** `bulk-index.mjs` batch-embeds and writes to SQLite

Each file becomes one memory entry:

- **Key:** `pattern:{type}:{slug}`
- **Namespace:** `pattern`
- **Tags:** `[source:auto-memory, type:{type}, project:{project}]`

---

## index-skills.sh

| Field | Value |
|-------|-------|
| **Purpose** | Index brana skill frontmatter into ruflo memory for semantic skill routing |
| **Usage** | `index-skills.sh` (all), `index-skills.sh --changed` (only skills with newer mtime) |
| **Dependencies** | ruflo CLI |
| **Status** | Active — canonical location is `system/scripts/index-skills.sh` |

Reads SKILL.md frontmatter (name, description, keywords, task_strategies, stream_affinity, group, effort) for each skill and stores as a memory entry. Skills are discoverable via `memory_search(namespace: "skills")`.

- **Key:** `skill:{name}`
- **Namespace:** `skills`
- **Tags:** `[source:brana, group:{group}, strategy:{each strategy}]`

Uses mtime marker (`/tmp/brana-skills-index-mtime`) for `--changed` mode to avoid reindexing unchanged skills.

---

## second-phase-check.sh

| Field | Value |
|-------|-------|
| **Purpose** | Weekly check for time-gated second-phase tasks (ADR-021) |
| **Usage** | `second-phase-check.sh [--dry-run]` |
| **Dependencies** | `jq`, tasks.json |

Reads tasks tagged "second-phase" or with soak gates. When a trigger condition is met, sets priority to P2 and updates context. Scheduled weekly (Mon 09:10).

---

## sync-state.sh

| Field | Value |
|-------|-------|
| **Purpose** | Unified brana state sync (ADR-015) |
| **Usage** | `sync-state.sh <push|pull|export|import> [--auto-commit]` |
| **Dependencies** | ruflo (for export/import), git |

Subcommands: `push` (cache → repos), `pull` (repos → cache), `export` (ruflo → repo JSON), `import` (repo JSON → ruflo). Used by session-start hook and daily scheduler. The `snapshot` subcommand was removed in t-614 — MEMORY.md is always loaded by CC, so repo snapshots are redundant. Companion file sync now limited to `event-log.md`; session state (sessions.md, handoff) stays in auto memory.

---

## task-id-lock.sh

| Field | Value |
|-------|-------|
| **Purpose** | Prevent task ID collisions across parallel worktree sessions |
| **Usage** | `task-id-lock.sh next-id <repo-path> <prefix>` |
| **Dependencies** | `flock` |

Uses `flock` on a shared lock file in `$GIT_COMMON_DIR` (shared across all worktrees). Returns the next available ID number. Called by the CLI when creating tasks.

---

## backup-knowledge.sh

| Field | Value |
|-------|-------|
| **Purpose** | Trigger brana-knowledge backup |
| **Usage** | `backup-knowledge.sh` |
| **Dependencies** | `~/enter_thebrana/brana-knowledge/backup.sh` (skips silently if not found) |

Thin wrapper that executes the brana-knowledge repo's own `backup.sh` script if it exists and is executable. Used by `/brana:maintain-specs` Step 8. No output or error if the script is absent.

---

## verify-counts.sh

| Field | Value |
|-------|-------|
| **Purpose** | Validate hardcoded counts in docs against actual filesystem |
| **Usage** | `verify-counts.sh` |
| **Dependencies** | None |

Compares numeric claims in documentation files (e.g., "14 rules", "24 skills") against actual file counts in `system/`. Reports mismatches with expected vs actual values. Used by `validate.sh` and as a standalone check after doc or system changes.

---

## backup-memory.sh

| Field | Value |
|-------|-------|
| **Purpose** | Rotating binary backup of ruflo memory database |
| **Usage** | `backup-memory.sh` (backup), `backup-memory.sh --restore [--date YYYYMMDD]` (restore), `backup-memory.sh --list` (list backups) |
| **Dependencies** | None (auto-detects DB path) |
| **Status** | Active — scheduled daily at 07:00 UTC via brana-scheduler (before sync-state push) |

Auto-detects the ruflo DB path (`~/.swarm/memory.db` > `~/.claude-flow/memory.db`). Copies the database to a dated backup file in `backups/` under the same directory. Keeps the last 7 dated copies. Skips 0-byte source files to avoid overwriting good backups with empty data.

### Subcommands

| Subcommand | Description |
|------------|-------------|
| *(default)* | Create a dated binary backup of the memory database |
| `--restore` | Restore the latest non-zero backup (or a specific date with `--date YYYYMMDD`) |
| `--list` | List available backups with sizes and dates |

---

## ruflo-batch-store.mjs

| Field | Value |
|-------|-------|
| **Purpose** | Fast batch `memory_store` via MCP stdio protocol |
| **Usage** | `cat entries.json \| node ruflo-batch-store.mjs` |
| **Dependencies** | Node.js, ruflo MCP server |
| **Status** | Active — canonical location is `system/scripts/ruflo-batch-store.mjs` |

Reads a JSON array of memory entries from stdin and stores each via a single long-lived ruflo MCP process using JSON-RPC over stdio. ~30ms per entry vs ~15s per CLI call.

### Input format

JSON array on stdin:

```json
[{"key": "k", "value": "v", "namespace": "ns", "tags": ["t1"], "upsert": true}, ...]
```

Each entry requires `key`, `value`, and `namespace`. Optional fields: `tags` (string array), `upsert` (boolean, default false).

---

## ruflo-mcp.sh

| Field | Value |
|-------|-------|
| **Purpose** | CWD wrapper to ensure ruflo MCP server finds its database |
| **Usage** | Configured as the MCP server command in Claude Code settings |
| **Dependencies** | ruflo (Node.js install) |

Changes to `$HOME` before executing ruflo, so the MCP server reads `~/.swarm/memory.db` instead of looking for `.swarm/` relative to whatever working directory Claude Code launches from. Passes all arguments through to the ruflo binary.

---

## statusline.sh

| Field | Value |
|-------|-------|
| **Purpose** | Claude Code statusline — model, project, branch, context %, lines changed, task metrics |
| **Location** | `system/statusline.sh` |
| **Dependencies** | jq, git |

### Task metrics cache

`post-tasks-validate.sh` writes a TSV cache (`.claude/tasks.statusline.tsv`) on every `tasks.json` write. The statusline reads this cache for zero-cost task display. Falls back to direct jq parsing on first run (before any task write).

**TSV fields (6 columns, tab-separated):**

| # | Field | Source |
|---|-------|--------|
| 1 | `phase_name` | First in_progress phase subject (before `:`, stripped `Phase ` prefix) |
| 2 | `done_count` | Count of completed tasks/subtasks |
| 3 | `total_count` | Count of all tasks/subtasks |
| 4 | `current_subject` | Subject of first in_progress task/subtask |
| 5 | `bug_count` | Count of open bugs |
| 6 | `build_step` | `build_step` field of first in_progress task/subtask (e.g. `SPECIFY`, `BUILD`, `TEST`, `SHIP`) |

### Segments displayed

| Segment | Condition | Example |
|---------|-----------|---------|
| Phase progress | Phase exists and total > 0 | `Ph A: 3/7` |
| Current task | In-progress task exists | `-> Do the thing` |
| Build step bracket | `build_step` is set | `[BUILD]` (magenta) |
| Bug count | Open bugs > 0 | `bug 2` (red) |
### Width detection

Statusline detects terminal width via `BRANA_STATUSLINE_COLS` env var (testing) or `tput cols` (production). When output would exceed width, segments are progressively dropped by priority:

| Priority | Segment | Drop order |
|----------|---------|------------|
| 11 | Model | Never drop |
| 10 | Project | Never drop |
| 9 | Branch | Never drop |
| 8 | CTX% | Never drop |
| 7 | Current task | Drop 5th |
| 6 | Build step | Drop 4th |
| 5 | Bugs | Drop 3rd |
| 4 | Phase progress | Drop 2nd |
| 3 | Session score | Drop 1st |
| 2 | Lines +/- | Drop 1st |
| 1 | Scheduler/CF | Drop 1st |

### Cache staleness

If `tasks.json` is newer than the cache file (mtime comparison), the statusline falls back to direct jq computation and refreshes the cache inline. This handles manual edits or CLI writes that bypass the hook.
