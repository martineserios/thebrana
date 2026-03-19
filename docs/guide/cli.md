# Brana CLI — User & Developer Guide

> Standalone Rust terminal interface for tasks, scheduler, file tracking, and system health.
> Works without Claude Code. Single binary, 12ms startup, zero Python dependency.

## Quick Start

```bash
# Build
cd ~/enter_thebrana/thebrana/system/cli/rust && cargo build --release

# Symlink (one time)
ln -sf $(pwd)/target/release/brana ~/.local/bin/brana

# Load shell aliases
source ~/enter_thebrana/thebrana/system/cli/aliases.sh

# Health check
brana doctor
```

## Commands

### `brana backlog` — Task Management

Mirrors `/brana:backlog` with the same themes, data model, and classification logic.
Full read/write — set, add, rollup, sync all work from CLI.

| Command | Alias | Description |
|---------|-------|-------------|
| `brana backlog status [--all] [--json]` | `bs` | Portfolio or project status overview |
| `brana backlog next [--tag T] [--stream S]` | `bn` | Next unblocked task by priority |
| `brana backlog query [filters...]` | `bq` | Filter tasks (AND logic): --tag, --status, --stream, --priority, --effort, --type, --parent, --branch, --search, --count, --output |
| `brana backlog search "text"` | `bsearch` | Free-text search across all fields |
| `brana backlog focus` | `bf` | Smart daily pick (priority x staleness - effort) |
| `brana backlog blocked` | `bb` | Blocked dependency chains |
| `brana backlog stale [--days 14]` | `bstale` | Tasks pending > N days |
| `brana backlog burndown [--period week]` | `bburn` | Created vs completed over time |
| `brana backlog diff` | `bdiff` | Semantic diff since last commit |
| `brana backlog context <id>` | `bctx` | Print task context, notes, description |
| `brana backlog get <id> [--field F]` | — | Full task JSON or single field |
| `brana backlog set <id> <field> <value>` | — | Set any field (supports +tag/-tag, --append) |
| `brana backlog add --json '{...}'` | — | Create new task from JSON |
| `brana backlog stats` | — | Aggregate by status/stream/priority/type |
| `brana backlog tags [--filter F]` | — | Tag inventory and filtering |
| `brana backlog roadmap [--json]` | — | Full tree: phases → milestones → tasks |
| `brana backlog tree <id> [--json]` | — | Subtree of a phase or milestone |
| `brana backlog rollup [--dry-run]` | — | Auto-complete parents (all children done) |
| `brana backlog sync [--dry-run] [--force]` | — | Sync tasks with GitHub Issues (parallel gh api) |

### `brana ops` — Scheduler & System Operations

Manages scheduler jobs, wraps system scripts, provides health checks.

| Command | Alias | Description | R/W |
|---------|-------|-------------|-----|
| `brana ops status` | `bo` | Dashboard: all jobs, last run, next trigger | Read |
| `brana ops health` | `boh` | Failures in 24h, collisions, lock contention | Read |
| `brana ops logs <job> [--tail 50]` | `bol` | View latest log for a job | Read |
| `brana ops history <job> [--last 10]` | — | Run history (pass/fail trend) | Read |
| `brana ops collisions` | `boc` | Detect same-project schedule conflicts | Read |
| `brana ops drift` | `bod` | Compare live config vs template | Read |
| `brana ops metrics <file>` | — | Session metrics from JSONL event file | Read |
| `brana ops run <job>` | `bor` | Manually trigger a job now | **Write** |
| `brana ops enable <job>` | — | Enable a disabled job | **Write** |
| `brana ops disable <job>` | — | Disable a job | **Write** |
| `brana ops sync [--auto-commit]` | `bosync` | Sync operational state (wraps sync-state.sh) | **Write** |
| `brana ops reindex` | `boreindex` | Reindex knowledge into ruflo memory | **Write** |

### `brana files` — Large File Tracking

Manage binary assets, models, and datasets via `.brana-files.json` manifest.

| Command | Description |
|---------|-------------|
| `brana files list` | List all tracked files |
| `brana files status` | Show ok/missing/modified state (SHA-256 verified) |
| `brana files add <name> <path> [--url U] [--r2-key K]` | Register file with hash |
| `brana files pull` | Download missing/modified files from remote URLs |
| `brana files push [--remote brana-r2]` | Upload tracked files to R2 via rclone |

### `brana` Root Commands

| Command | Alias | Description |
|---------|-------|-------------|
| `brana doctor` | `bd` | Health check: git, tasks.json, scheduler, themes |
| `brana validate <file>` | — | Validate tasks.json schema |
| `brana portfolio` | — | List client/project paths from tasks-portfolio.json |
| `brana run <id> [--spawn]` | — | Create worktree + set in_progress, optionally spawn tmux |
| `brana queue [--max 5] [--auto]` | — | Show next unblocked tasks with model recommendations |
| `brana agents [kill <id>]` | — | List or kill active agents |
| `brana transcribe <file> [--model base]` | — | Audio to text via whisper.cpp |
| `brana version` | `bv` | Show CLI version |

## Theming

The CLI reads `~/.claude/tasks-config.json` for the active theme and loads icon/color definitions from `system/cli/themes.json`.

**Available themes:** `classic` (default), `emoji`, `minimal`

| Element | Classic | Emoji | Minimal |
|---------|---------|-------|---------|
| Done | ✓ | ✅ | ● |
| Active | ← | 🔨 | ◐ |
| Pending | → | 🔲 | ○ |
| Blocked | · | 🔒 | ⊘ |
| Parked | · | 💤 | ◌ |

## Architecture

```
User terminal
    │
    └── brana (Rust, single binary)
            │
            ├── main.rs          ← dispatcher
            ├── cli.rs           ← clap derive structs
            ├── commands/        ← handlers (backlog, ops, files, run, doctor, misc)
            ├── tasks.rs         ← core task loading, filtering, classification
            ├── files.rs         ← manifest, SHA-256, download/upload
            ├── transcribe.rs    ← whisper.cpp shell-out
            ├── sync.rs          ← GitHub Issues sync (parallel gh api)
            ├── themes.rs        ← ANSI theme rendering
            └── util.rs          ← git helpers, path resolution
```

### Data Sources

| Source | Path | Used by |
|--------|------|---------|
| Tasks | `.claude/tasks.json` (project-relative, worktree-aware) | `backlog *` |
| Portfolio | `~/.claude/tasks-portfolio.json` | `backlog status --all`, `portfolio` |
| Theme config | `~/.claude/tasks-config.json` | all rendering |
| Theme defs | `system/cli/themes.json` | all rendering |
| Scheduler config | `~/.claude/scheduler/scheduler.json` | `ops *` |
| Scheduler status | `~/.claude/scheduler/last-status.json` | `ops status/health` |
| Scheduler logs | `~/.claude/scheduler/logs/<job>/` | `ops logs/history` |
| File manifest | `.brana-files.json` (project root) | `files *` |
| Agents cache | `~/.claude/agents.json` | `run --spawn`, `agents` |

### Task Classification

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

## For Developers

### Module Structure

```
system/cli/rust/src/
├── main.rs              # Entry point, dispatcher
├── cli.rs               # Pure clap derive structs (no logic)
├── commands/
│   ├── mod.rs           # Module exports
│   ├── backlog.rs       # Task query/filter/display handlers
│   ├── ops.rs           # Scheduler status/health/management
│   ├── files.rs         # File manifest add/pull/push handlers
│   ├── run.rs           # Worktree creation, agent spawning
│   ├── doctor.rs        # Health checks
│   └── misc.rs          # Version, validate, portfolio, transcribe
├── tasks.rs             # Core task model + 74 unit tests
├── files.rs             # Manifest, SHA-256, download/upload + 7 tests
├── transcribe.rs        # Whisper.cpp integration
├── sync.rs              # GitHub Issues sync (parallel threads)
├── themes.rs            # ANSI theme loading
├── util.rs              # Git helpers, path resolution
├── query.rs             # brana-query binary (fast JSON filter)
└── fmt.rs               # brana-fmt binary (themed renderer)
```

### Adding a New Subcommand

1. Add clap enum variant to `cli.rs` (e.g., `FilesCmd::NewCmd { args }`)
2. Add handler in `commands/<area>.rs`
3. Wire dispatch in `main.rs`
4. Add tests in the module (`#[cfg(test)] mod tests`)
5. Build: `cd system/cli/rust && cargo build --release`
6. Copy to plugin cache: `cp target/release/brana ~/.claude/plugins/cache/brana/brana/1.0.0/cli/rust/target/release/brana`
7. Update this guide

### Key Design Decisions

- **Full Rust, no Python** — single static binary, 12ms startup, zero runtime deps
- **Modular commands** — `cli.rs` has clap structs only, `commands/` has logic
- **Worktree-aware** — `util::find_tasks_file()` uses `git rev-parse --git-common-dir`
- **Parallel sync** — `std::thread::scope` + `gh api`, no async runtime (saves binary size)
- **Pure Rust SHA-256** — no sha2 crate dependency for file tracking
- **themes.json is canonical** — single source of truth for both CLI and skills

## Changelog

- 2026-03-18: Added `brana files` subcommand (t-574). Pure Rust SHA-256, manifest tracking.
- 2026-03-18: Modular CLI refactor (t-568). Split cli.rs into commands/ modules.
- 2026-03-16: Added `brana run`, `brana agents`, `brana queue` (t-525). Mission control.
- 2026-03-15: Added `brana transcribe` (t-080). Whisper.cpp integration.
- 2026-03-14: Initial Rust CLI (t-428). Replaced Python/typer.
