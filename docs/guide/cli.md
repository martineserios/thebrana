# Brana CLI — User & Developer Guide

> Standalone terminal interface for tasks, scheduler, and system health.
> Works without Claude Code. Three layers: Python orchestrates, Rust accelerates, Bash wraps.

## Quick Start

```bash
# Install (dev mode)
cd ~/enter_thebrana/thebrana
uv pip install -e .

# Or run without install
uv run brana --help

# Load shell aliases
source system/cli/aliases.sh

# Health check
brana doctor
```

## Commands

### `brana backlog` — Task Management

Mirrors `/brana:backlog` with the same themes, data model, and classification logic.
Read-only — writes go through Claude Code skills (which have hooks, validation, GitHub sync).

| Command | Alias | Description |
|---------|-------|-------------|
| `brana backlog status` | `bs` | Portfolio or project status overview |
| `brana backlog next` | `bn` | Next unblocked task by priority |
| `brana backlog query --tag X --status Y` | `bq` | Filter tasks (AND logic) |
| `brana backlog search "text"` | `bsearch` | Free-text search across all fields |
| `brana backlog focus` | `bf` | Smart daily pick (priority x staleness - effort) |
| `brana backlog blocked` | `bb` | Blocked dependency chains |
| `brana backlog stale --days 14` | `bstale` | Tasks pending > N days |
| `brana backlog burndown --period week` | `bburn` | Created vs completed over time |
| `brana backlog diff` | `bdiff` | Semantic diff since last commit |
| `brana backlog context t-428` | `bctx` | Print task context, notes, description |
| `brana backlog graph ph-001` | `bgraph` | ASCII dependency tree |

**Options available on most commands:**
- `--project NAME` — target a specific project
- `--wide` — tabular output (on `status`, `query`)
- `--all` — cross-client view (on `status`)

### `brana ops` — Scheduler & System Operations

Read + write. Manages scheduler jobs, wraps system scripts, provides health checks.

| Command | Alias | Description | R/W |
|---------|-------|-------------|-----|
| `brana ops status` | `bo` | Dashboard: all jobs, last run, next trigger | Read |
| `brana ops health` | `boh` | Failures in 24h, collisions, lock contention | Read |
| `brana ops logs <job>` | `bol` | View latest log for a job | Read |
| `brana ops history <job>` | — | Run history (pass/fail trend) | Read |
| `brana ops collisions` | `boc` | Detect same-project schedule conflicts | Read |
| `brana ops drift` | `bod` | Compare live config vs template | Read |
| `brana ops run <job>` | `bor` | Manually trigger a job now | **Write** |
| `brana ops enable <job>` | — | Enable a disabled job | **Write** |
| `brana ops disable <job>` | — | Disable a job | **Write** |
| `brana ops sync` | `bosync` | Sync operational state (wraps sync-state.sh) | **Write** |
| `brana ops reindex` | `boreindex` | Reindex knowledge into ruflo memory | **Write** |

### `brana` Root Commands

| Command | Alias | Description |
|---------|-------|-------------|
| `brana version` | `bv` | Show brana-cli, plugin, ruflo versions |
| `brana doctor` | `bd` | Health check: git, tasks.json, scheduler, ruflo, bootstrap |
| `brana --version` | — | Short version output |

## Theming

The CLI reads `~/.claude/tasks-config.json` for the active theme and loads icon/color definitions from `system/cli/themes.json` (the single source of truth shared with `/brana:backlog`).

```bash
# Set theme (persists in ~/.claude/tasks-config.json)
# Use /brana:backlog theme <name> from Claude Code, or edit the file directly
```

**Available themes:** `classic` (default), `emoji`, `minimal`

| Element | Classic | Emoji | Minimal |
|---------|---------|-------|---------|
| Done | ✓ | ✅ | ● |
| Active | ← | 🔨 | ◐ |
| Pending | → | 🔲 | ○ |
| Blocked | · | 🔒 | ⊘ |
| Parked | · | 💤 | ◌ |

## Rust Accelerator

Two compiled binaries provide 34x speedup for JSON-heavy operations.
Python auto-detects and delegates to Rust when available; falls back to pure Python if not.

### `brana-query` — Fast JSON Task Filter

```bash
# Build (one time)
cd system/cli/rust && cargo build --release

# Direct usage
brana-query --file .claude/tasks.json --tag scheduler --status pending
brana-query --file .claude/tasks.json --search "JWT" --output ids
brana-query --file .claude/tasks.json --count --stream roadmap

# Pipeline with brana-fmt
brana-query --file .claude/tasks.json --tag auth | brana-fmt --theme emoji
```

**Options:**
- `--file PATH` — tasks.json path (reads stdin if omitted)
- `--tag TAG` — filter by tag
- `--status STATUS` — filter by classified status (done/active/pending/blocked/parked)
- `--stream STREAM` — filter by stream
- `--priority P0-P3` — filter by priority
- `--effort S/M/L/XL` — filter by effort
- `--search TEXT` — free-text search
- `--output json|ids` — output format
- `--count` — output count only
- `--types task,subtask` — task types to include

### `brana-fmt` — Themed Line Renderer

```bash
# Pipe tasks in, get styled output
echo '{"id":"t-001","subject":"Test","status":"pending"}' | brana-fmt --theme emoji

# Progress bar
brana-fmt --progress 5 8 --theme minimal
# Output: ━━━━━╍╍╍ 5/8

# With themes.json path
brana-fmt --themes-file system/cli/themes.json --theme classic
```

### Shell Functions (Rust-Accelerated)

Source `aliases.sh` to get these bash functions that bypass Python entirely:

```bash
# Fast query (pure Rust)
bfq --tag scheduler --status pending

# Fast query + themed output (Rust pipeline)
bfqf --tag auth --theme emoji

# Fast count
bfc --tag scheduler
```

## Shell Aliases

```bash
# Add to ~/.bashrc or ~/.zshrc
source ~/enter_thebrana/thebrana/system/cli/aliases.sh
```

Full alias list:

| Alias | Expands to |
|-------|-----------|
| `bq` | `brana backlog query` |
| `bn` | `brana backlog next` |
| `bf` | `brana backlog focus` |
| `bs` | `brana backlog status` |
| `bb` | `brana backlog blocked` |
| `bo` | `brana ops status` |
| `boh` | `brana ops health` |
| `bd` | `brana doctor` |
| `bfq` | Rust-accelerated query |
| `bfqf` | Rust query + fmt pipeline |
| `bfc` | Rust count |
| `bbackup` | `backup-knowledge.sh` |
| `bvalidate` | `validate.sh` |

## Architecture

```
User terminal
    │
    ├── brana (Python/typer) ──→ main.py ──→ backlog.py / ops.py
    │       │                                    │
    │       ├── theme.py ←── themes.json         │
    │       │                                    │
    │       └── _rust_query() ──→ brana-query ───┘  (auto-fallback to Python)
    │
    ├── bfq / bfqf (Bash) ──→ brana-query | brana-fmt  (pure Rust pipeline)
    │
    └── bbackup / bvalidate (Bash) ──→ existing .sh scripts
```

### Data Sources

| Source | Path | Used by |
|--------|------|---------|
| Tasks | `.claude/tasks.json` (project-relative) | `backlog *` |
| Portfolio | `~/.claude/tasks-portfolio.json` | `backlog status --all` |
| Theme config | `~/.claude/tasks-config.json` | all rendering |
| Theme defs | `system/cli/themes.json` | all rendering |
| Scheduler config | `~/.claude/scheduler/scheduler.json` | `ops *` |
| Scheduler status | `~/.claude/scheduler/last-status.json` | `ops status/health` |
| Scheduler logs | `~/.claude/scheduler/logs/<job>/` | `ops logs/history` |
| Template config | `system/scheduler/scheduler.template.json` | `ops drift` |

### Task Classification

Both CLI and `/brana:backlog` share the same logic:

```
completed/cancelled → done
in_progress         → active
blocked_by unmet    → blocked
tag "parked"        → parked
otherwise           → pending
```

### Focus Score Formula

```
score = priority_weight (P0=400, P1=300, P2=200, P3=100, null=50)
      + staleness_days × 2
      - effort_weight (S=10, M=20, L=30, XL=40)
      - blocked_depth × 50
```

## Integration with Brana System

### Where CLI replaces existing patterns

| Current pattern | Where | CLI replacement |
|----------------|-------|-----------------|
| `jq` task queries in session-start.sh | hooks | `brana-query --file tasks.json` (34x faster) |
| Manual scheduler.json reading | scheduler skill | `brana ops status/health` |
| `systemctl --user start/stop` in scripts | hooks, skills | `brana ops run/enable/disable` |
| `sync-state.sh push` in scheduler | scheduler.json | `brana ops sync --auto-commit` |
| `index-knowledge.sh` in scheduler | scheduler.json | `brana ops reindex` |
| Venture project detection (2 hooks) | session-start*.sh | `brana doctor` (project type) |
| Task validation schema checks | post-tasks-validate.sh | `brana doctor` (duplicate IDs) |
| `backup-knowledge.sh` in close skill | close/SKILL.md | `bbackup` alias |

### Where CLI complements (not replaces)

| Brana component | CLI role |
|----------------|---------|
| `/brana:backlog status` | `brana backlog status` — same view, no Claude Code needed |
| `/brana:backlog next` | `brana backlog next` — quick check from terminal |
| `/brana:build` classify step | `brana backlog focus` — pre-decision daily pick |
| `/brana:close` drift detection | `brana ops drift` — standalone drift check |
| `/brana:review` health check | `brana ops health` — scheduler subset of review |
| Session-start hook | `brana doctor` — manual health check anytime |

### Where CLI enables new workflows

1. **Morning routine:** `bf` (focus pick) → open Claude Code → `/brana:backlog start`
2. **Quick check between sessions:** `bo` + `boh` — is everything healthy?
3. **Pipeline scripting:** `bfq --tag scheduler --count` in cron jobs or CI
4. **Stale task hygiene:** `bstale --days 30` weekly to spot forgotten work
5. **Pre-commit check:** `bdiff` before committing tasks.json changes
6. **Dependency analysis:** `bb` + `bgraph ph-001` for planning conversations

## For Developers

### File Structure

```
system/cli/
├── __init__.py          # Package init
├── main.py              # Root app: version, doctor, --version, subcommand registration
├── config.py            # Paths, JSON loading, project detection, classify_task()
├── theme.py             # Theme loading (cached), icon/color/progress_bar/task_line helpers
├── themes.json          # Canonical theme definitions (single source of truth)
├── backlog.py           # 11 subcommands + Rust accelerator integration
├── ops.py               # 11 subcommands (read + write)
├── aliases.sh           # Shell aliases + Rust pipeline functions
└── rust/
    ├── Cargo.toml       # Two binaries: brana-query, brana-fmt
    ├── src/main.rs      # brana-query: JSON filter with clap args
    ├── src/fmt.rs        # brana-fmt: themed ANSI line renderer
    └── .gitignore       # Excludes target/
```

### Adding a New Command

1. Choose the right module: `backlog.py` (task ops) or `ops.py` (system ops)
2. Add the function with `@backlog_app.command()` or `@ops_app.command()`
3. Use `get_theme()` for themed output, `console.print()` for Rich rendering
4. Add a test in `tests/test_cli.py`
5. Add an alias in `aliases.sh`
6. Update this guide

### Adding a Rust Binary

1. Add a `[[bin]]` section to `system/cli/rust/Cargo.toml`
2. Create `src/<name>.rs` with `clap::Parser` for args
3. Build: `cd system/cli/rust && cargo build --release`
4. Wire into Python: add `_find_rust_binary("<name>")` call in the relevant `.py` module
5. Add bash function in `aliases.sh` for direct Rust access

### Testing

```bash
# Run all CLI tests
uv run pytest tests/test_cli.py -v

# Run specific test class
uv run pytest tests/test_cli.py::TestCriticalFixes -v

# Rust tests
cd system/cli/rust && cargo test
```

### Key Design Decisions

- **Read-only for tasks** — skills have hooks, validation, GitHub sync that CLI can't replicate
- **Scheduler writes allowed** — no skill equivalent for systemd management
- **Rust auto-fallback** — `_rust_query()` returns `None` if binary absent; Python takes over
- **themes.json is canonical** — both CLI and SKILL.md reference it; prevents drift
- **`@lru_cache` on theme loading** — themes.json read once per process, not per call
- **Job name validation** — regex `^[a-zA-Z0-9_-]+$` prevents path traversal in subprocess calls
- **Circular dependency protection** — `_build_blocked_chain` tracks visited set
