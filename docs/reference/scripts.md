# Scripts Reference

Helper scripts that support hooks, skills, and maintenance workflows. Located in `system/scripts/`.

## cf-env.sh

| Field | Value |
|-------|-------|
| **Purpose** | Locate the claude-flow binary |
| **Usage** | `source cf-env.sh` -- sets `$CF` variable |
| **Dependencies** | None (graceful if claude-flow is absent) |

Search order:
1. nvm global install: `$HOME/.nvm/versions/node/*/bin/claude-flow`
2. PATH lookup: `command -v claude-flow`
3. npx fallback: `npx claude-flow`

Exports `$CF` (empty string if not found). A duplicate copy exists at `system/hooks/lib/cf-env.sh` for the plugin hooks to use without depending on bootstrap installation.

---

## memory-store.sh

| Field | Value |
|-------|-------|
| **Purpose** | Store a key-value pair in claude-flow memory with auto-fallback |
| **Usage** | `memory-store.sh -k KEY -v VALUE [-n NAMESPACE] [-t TAGS]` |
| **Dependencies** | `cf-env.sh` (sourced automatically) |

Attempts to store via `claude-flow memory store`. If claude-flow is unavailable or the store fails, falls back to appending the entry to the first project `MEMORY.md` file found in `~/.claude/projects/*/memory/`.

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
| **Purpose** | Index brana-knowledge dimension docs into claude-flow memory for semantic search |
| **Usage** | `index-knowledge.sh` (all), `index-knowledge.sh file.md` (specific), `index-knowledge.sh --changed` (git-changed only) |
| **Dependencies** | claude-flow with real embeddings (not hash-fallback), `@xenova/transformers` |
| **Status** | Deprecated -- canonical copy at `system/skills/knowledge/index-knowledge.sh`. Kept for backward compatibility (post-commit hook, scheduler). |

Splits each dimension doc by `##` headings. Each section becomes a memory entry:

- **Key:** `knowledge:dimension:{doc-slug}:{section-slug}`
- **Namespace:** `knowledge`
- **Tags:** `source:brana-knowledge,type:dimension,doc:{filename}`
- **Value:** Section content, truncated to 2000 characters

Validates that claude-flow produces real ONNX embeddings (not hash-fallback, which produces 768-dim instead of 384-dim vectors).

### Modes

| Mode | Trigger | Use case |
|------|---------|----------|
| `index-knowledge.sh` | No args | Full reindex of all dimension docs |
| `index-knowledge.sh file1.md` | Filename args | Index specific files |
| `index-knowledge.sh --changed` | `--changed` flag | Index only git-changed files (for post-commit hook) |

---

## generate-index.sh

| Field | Value |
|-------|-------|
| **Purpose** | Generate `dimensions/INDEX.md` from dimension doc headers |
| **Usage** | `generate-index.sh [knowledge-dir]` |
| **Dependencies** | None |
| **Status** | Deprecated -- canonical copy at `system/skills/knowledge/generate-index.sh`. Kept for backward compatibility. |

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

## spec_graph.py

| Field | Value |
|-------|-------|
| **Purpose** | Generate a JSON dependency graph of all spec documents |
| **Usage** | `uv run python3 system/scripts/spec_graph.py generate [--output PATH]` |
| **Dependencies** | Python 3 (stdlib only) |

Parses all markdown files in `docs/` and `docs/dimensions/` (symlink), extracts cross-reference links and `system/` file mentions, and outputs a JSON dependency graph.

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `generate` | Parse docs, build graph, write JSON |

### Arguments (generate)

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--output` | No | `docs/spec-graph.json` | Output file path |

### Output

JSON with `_meta` (stats) and `nodes` (per-doc references, referenced_by, impl_files). See [spec-graph workflow guide](../guide/workflows/spec-graph.md) for schema details.

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

## backup-knowledge.sh

| Field | Value |
|-------|-------|
| **Purpose** | Trigger brana-knowledge backup |
| **Usage** | `backup-knowledge.sh` |
| **Dependencies** | `~/enter_thebrana/brana-knowledge/backup.sh` (skips silently if not found) |

Thin wrapper that executes the brana-knowledge repo's own `backup.sh` script if it exists and is executable. Used by `/brana:maintain-specs` Step 8. No output or error if the script is absent.
