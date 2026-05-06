# Brana CLI — User & Developer Guide

> Standalone Rust terminal interface for tasks, scheduler, file tracking, and system health.
> Works without Claude Code. Single binary, 12ms startup, zero Python dependency.

## Quick Start

```bash
# Build (requires OpenSSL headers — no pkg-config on this system)
cd ~/enter_thebrana/thebrana/system/cli/rust
OPENSSL_LIB_DIR=/usr/lib/x86_64-linux-gnu OPENSSL_INCLUDE_DIR=/usr/include/openssl cargo build --release

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
| `brana backlog set <id> <field> <value>` | — | Set any field (supports +tag/-tag, --append). `priority` and `status` are validated against canonical enums. |
| `brana backlog add --json '{...}'` | — | Create new task from JSON. `priority` (P0–P3 or null) and `status` (pending/in_progress/completed/cancelled) are validated. |
| `brana backlog stats` | — | Aggregate by status (raw)/state (synthetic)/stream/priority/type |
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

### `brana feed` — RSS/Atom Feed Polling

Monitor blogs, Substacks, YouTube channels, and GitHub releases via RSS/Atom feeds with HTTP conditional requests (ETag).

| Command | Description |
|---------|-------------|
| `brana feed add <url> [--name N]` | Subscribe to a feed |
| `brana feed list` | List subscribed feeds |
| `brana feed poll [--all]` | Fetch new entries from feeds |
| `brana feed remove <name>` | Unsubscribe from a feed |
| `brana feed status` | Show feed health (last poll, entry count) |

### `brana inbox` — Gmail Newsletter Management

Multi-account Gmail via IMAP with OS keyring credential storage.

| Command | Description |
|---------|-------------|
| `brana inbox add-account <email>` | Register a Gmail account |
| `brana inbox set-password <email>` | Set/update app password in OS keyring |
| `brana inbox add <email> <label>` | Subscribe to a label/folder |
| `brana inbox list` | List subscribed accounts and labels |
| `brana inbox poll [--all]` | Fetch new messages |
| `brana inbox remove <email>` | Remove an account |
| `brana inbox status` | Show inbox health (last poll, message count) |

### `brana skills` — Skill Discovery & Indexing

| Command | Description |
|---------|-------------|
| `brana skills suggest --task <id>` | Recommend skills for a task based on context matching (ADR-025) |
| `brana skills suggest --query <text>` | Recommend skills for a free-text query |
| `brana skills search <query>` | Search local skills by keyword (name, description, keywords) |
| `brana skills list` | List all local skills with metadata (JSON) |
| `brana skills reindex` | Force full reindex of skills into ruflo memory (deletes mtime marker) |
| `brana skills reindex --changed` | Only reindex skills modified since last run |
| `brana skills usage [--days N] [--cull-threshold N] [--json]` | Show skill invocation counts from JSONL telemetry; flag low-use cull candidates |

### `brana knowledge` — Knowledge Base Indexing

| Command | Description |
|---------|-------------|
| `brana knowledge reindex` | Full reindex of all 7 doc categories + orphan cleanup |
| `brana knowledge reindex --changed` | Index only git-changed files (for post-commit hook) |
| `brana knowledge reindex --patterns` | Reindex pattern files from project memory dirs |
| `brana knowledge status` | Show entry count + last indexed timestamp |

### `brana` Root Commands

| Command | Alias | Description |
|---------|-------|-------------|
| `brana doctor` | `bd` | Health check: git, tasks.json, scheduler, themes |
| `brana validate <file>` | — | Validate tasks.json schema |
| `brana portfolio` | — | List client/project paths from tasks-portfolio.json |
| `brana run <id> [--spawn]` | — | Create worktree + set in_progress, optionally spawn tmux |
| `brana queue [--max 5] [--auto]` | — | Show next unblocked tasks with model recommendations |
| `brana agents [kill <id>]` | — | List or kill active agents |
| `brana transcribe <file> [--model base]` | — | Audio to text via whisper.cpp (`libwhisper.so.1` injected automatically from `$HOME/.local/lib`) |
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

- 2026-04-08: `find_tasks_file` auto-init: creates empty `{"tasks":[]}` on first use. CWD fallback added for non-git projects (t-1090).
- 2026-03-18: Added `brana files` subcommand (t-574). Pure Rust SHA-256, manifest tracking.
- 2026-03-18: Modular CLI refactor (t-568). Split cli.rs into commands/ modules.
- 2026-03-16: Added `brana run`, `brana agents`, `brana queue` (t-525). Mission control.
- 2026-03-15: Added `brana transcribe` (t-080). Whisper.cpp integration.
- 2026-03-14: Initial Rust CLI (t-428). Replaced Python/typer.

## Field Notes

### 2026-04-08: Auto-init beats error-out for project-scoped state files
`find_tasks_file()` previously returned `None` when a project had no `.claude/tasks.json`, causing a hard CLI error. State files with a well-defined empty form (`{"tasks":[]}`) should lazy-create on first call rather than failing. Applied in `brana-core/src/util.rs`. Pattern applies to any future per-project JSON state (feeds, inbox, files manifest).
Source: session 2026-04-08 / t-1090

### 2026-04-08: Non-git projects need CWD fallback in all path helpers
Any helper using `git rev-parse` exclusively will break on non-git project dirs. `mandawa` and `prediktive-prep` have no `.git`. Fix: terminate every path-discovery chain with `if let Ok(cwd) = std::env::current_dir()`. `find_project_root()` in `util.rs` still lacks this fallback (tracked: t-1089).
Source: session 2026-04-08 / t-1089

### 2026-04-09: brana transcribe requires LD_LIBRARY_PATH on user-local installs
**Fixed 2026-05-06 (t-1282).** `transcribe()` now injects `LD_LIBRARY_PATH=$HOME/.local/lib` directly into the whisper-cli subprocess via `Command::env()`, prepending to any existing value. No manual env var needed. Original issue: `libwhisper.so.1: cannot open shared object file` on systems where whisper was installed to `~/.local/lib/` (not in ldconfig). Errata #113.
Source: /brana:onboard legai session 2026-04-09 / fixed t-1282 2026-05-06
