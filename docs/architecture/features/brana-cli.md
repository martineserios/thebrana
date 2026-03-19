# Feature: Brana CLI — Standalone Terminal Interface

**Date:** 2026-03-14
**Status:** shipped
**Task:** t-428
**ADR:** ADR-022

## Problem

No way to check task status, scheduler health, or system state from a terminal without opening Claude Code. Ad-hoc jq chains are fragile and produce raw JSON instead of themed, readable output.

## Decision Record (frozen 2026-03-14)

> Do not modify after acceptance.

**Context:** t-424 spike evaluated CLI frameworks. Python (typer+rich) was initially selected, but t-427 spike revealed that a Rust implementation provided faster startup (~12ms vs ~200ms), smaller deployment (single binary), and better long-term maintainability. Rust was adopted before v1 shipped.

**Decision:** Build `brana` CLI as a Rust binary, deeply integrated with `/brana:backlog` theme system and data model. Three command groups: `backlog` (task management), `ops` (scheduler/system operations), and `files` (large file tracking via `.brana-files.json`), plus top-level utilities (doctor, validate, portfolio, run, queue, agents, version). Both read and write operations are supported — writes include `set`, `add`, `rollup`, `sync`, and all `files` mutations.

**Consequences:** Terminal-native access, consistent themed output, fast startup, single-binary deployment, shell completions.

**Historical note:** The original Python/typer implementation (t-424) was replaced by Rust (t-427) before the first release. The Python code is no longer in use.

## Constraints

- Task writes supported: `set` (field mutations), `add` (new tasks), `rollup` (parent auto-complete), `sync` (GitHub Issues sync)
- Scheduler writes allowed: `enable`, `disable`, `run` have no skill equivalent
- Must render identically to `/brana:backlog` for overlapping views (status, next)
- Theme definitions live in `themes.json` (single source of truth for both CLI and SKILL.md)
- Installed via `cargo build --release`; binary symlinked to `~/.local/bin/brana`

## Scope

### `brana backlog` — 20 subcommands

| Command | Args | Description | Read/Write |
|---------|------|-------------|------------|
| `next` | `[project]`, `--stream`, `--tag` | Next unblocked task by priority | Read |
| `query` | `--tag`, `--status`, `--stream`, `--priority`, `--effort`, `--project` | Filter tasks with AND logic | Read |
| `focus` | `[project]` | Smart daily pick (see ranking formula below) | Read |
| `search` | `<text>` | Free-text search across subjects, descriptions, contexts | Read |
| `status` | `[project]`, `--all`, `--wide` | Portfolio or project status (mirrors backlog status) | Read |
| `blocked` | `[project]` | Blocked dependency chains — what's stuck and why | Read |
| `stale` | `--days N` (default 14) | Tasks pending > N days with no activity | Read |
| `context` | `<id>` | Print task context inline | Read |
| `diff` | — | Semantic diff of tasks.json since last commit (added/removed/status changed) | Read |
| `burndown` | `--period week\|month` | Completed vs created over time | Read |
| `rollup` | — | Auto-complete parents whose children are all done | **Write** |
| `set` | `<id> <field> <value>` | Set a field on a task | **Write** |
| `add` | `<json>` | Add a new task from JSON | **Write** |
| `get` | `<id> [field]` | Get full task JSON or a single field | Read |
| `stats` | — | Aggregate stats by status, stream, priority, type | Read |
| `tags` | — | Tag inventory, filtering, and bulk management | Read |
| `roadmap` | — | Full roadmap tree (phases → milestones → tasks) | Read |
| `tree` | `<phase-or-milestone-id>`, `--depth N` | Subtree of a phase or milestone (ASCII) | Read |
| `sync` | — | Sync tasks with GitHub Issues (parallel, via `gh api`) | **Write** |
| `help` | — | Print help | — |

### `brana ops` — 12 subcommands

| Command | Args | Description | Read/Write |
|---------|------|-------------|------------|
| `status` | `--wide` | Dashboard: all jobs, last run, next trigger, health | Read |
| `health` | — | Aggregate: failures in 24h, missed runs, lock contention | Read |
| `collisions` | — | Detect same-project schedule conflicts | Read |
| `drift` | — | Compare live timers vs template config | Read |
| `logs` | `<job-name>`, `--tail N` | View logs for a job | Read |
| `history` | `<job-name>`, `--last N` | Run history (pass/fail trend) | Read |
| `run` | `<job-name>` | Manually trigger a job now | **Write** |
| `enable` | `<job-name>` | Enable a disabled job | **Write** |
| `disable` | `<job-name>` | Disable a job | **Write** |
| `sync` | — | Sync operational state (wraps sync-state.sh) | **Write** |
| `reindex` | — | Reindex knowledge (wraps index-knowledge.sh) | **Write** |
| `metrics` | — | Compute session metrics from JSONL event file | Read |

### `brana files` — 5 subcommands

| Command | Args | Description | Read/Write |
|---------|------|-------------|------------|
| `list` | — | List all tracked large files from `.brana-files.json` | Read |
| `status` | — | Show ok/missing/modified state of tracked files | Read |
| `add` | `<name> <path> [--url U] [--r2-key K]` | Register a file with SHA-256 hash | **Write** |
| `pull` | — | Download missing/modified files from remote URLs | **Write** |
| `push` | `[--remote R]` | Upload tracked files to R2 via rclone | **Write** |

Implementation: [system/cli/rust/src/files.rs](../../../system/cli/rust/src/files.rs) (data model, manifest I/O, SHA-256 verification), [system/cli/rust/src/commands/files.rs](../../../system/cli/rust/src/commands/files.rs) (CLI handlers).

### `brana` top-level — 8 subcommands

| Command | Description |
|---------|-------------|
| `doctor` | Health check: ruflo, systemd, tasks.json validity (incl. duplicate IDs), bootstrap |
| `validate` | Validate a tasks.json file (JSON + schema) |
| `portfolio` | List portfolio client/project paths from tasks-portfolio.json |
| `run` | Run a task: create worktree, print claude command, set in_progress |
| `queue` | Show next unblocked tasks with model recommendations, optionally auto-spawn |
| `agents` | List or manage active agents |
| `files` | Large file tracking via `.brana-files.json` manifest (SHA-256, HTTP/R2 remotes) |
| `version` | Show brana system version, plugin version, ruflo version |

## Research

- t-424 spike: typer + rich recommended over click, pure bash, Go/Rust
- t-427 spike: Rust adopted — single binary, ~12ms startup (34x faster than Python), smaller deployment
- Architecture: Rust binary with JSON parsing (serde_json), themed ANSI output
- Shell completions via clap derive macros

## Design

### Data flow

```
themes.json ─────→ theme rendering (ANSI) ──→ terminal
tasks.json ──────→ serde_json parse ──→ filter/sort ──→ themed output ──→ terminal
scheduler.json ──→ serde_json parse ──→ aggregate ──→ themed output ──→ terminal
systemctl ───────→ subprocess ──→ themed output ──→ terminal
```

### Theme integration — `themes.json` as single source

```json
{
  "classic": {
    "icons": {"done": "✓", "active": "←", "pending": "→", "blocked": "·", "parked": "·"},
    "bars": {"fill": "█", "empty": "░"},
    "tree": {"branch": "├──", "last": "└──", "pipe": "│"}
  },
  "emoji": {
    "icons": {"done": "✅", "active": "🔨", "pending": "🔲", "blocked": "🔒", "parked": "💤"},
    "bars": {"fill": "█", "empty": "░"},
    "tree": {"branch": "├──", "last": "└──", "pipe": "│"},
    "health": {"done": "🟢", "active": "🟡", "blocked": "🔴"},
    "priority_high": "⚡",
    "blocked_ref": "⛓"
  },
  "minimal": {
    "icons": {"done": "●", "active": "◐", "pending": "○", "blocked": "⊘", "parked": "◌"},
    "bars": {"fill": "━", "empty": "╍"},
    "tree": {"branch": "├──", "last": "└──", "pipe": "│"},
    "blocked_ref": "←"
  }
}
```

### Task classification (shared with backlog)

```rust
fn classify_task(task: &Value, all_tasks: &[Value]) -> &'static str {
    if task["status"] == "completed" { return "done"; }
    if task["status"] == "in_progress" { return "active"; }
    if let Some(blocked_by) = task["blocked_by"].as_array() {
        let completed: HashSet<_> = all_tasks.iter()
            .filter(|t| t["status"] == "completed")
            .filter_map(|t| t["id"].as_str())
            .collect();
        if !blocked_by.iter().all(|b| completed.contains(b.as_str().unwrap_or(""))) {
            return "blocked";
        }
    }
    if task.get("tags").and_then(|t| t.as_array())
        .map_or(false, |tags| tags.iter().any(|t| t == "parked")) {
        return "parked";
    }
    "pending"
}
```

### `backlog focus` ranking formula

```
score = (priority_weight * 100)       # P0=400, P1=300, P2=200, P3=100, null=50
      + (staleness_days * 2)           # older tasks get a boost
      - (effort_weight * 10)           # S=10, M=20, L=30, XL=40 — prefer quick wins
      - (blocked_depth * 50)           # tasks deep in blocked chains penalized
```

Top 3 by score shown. User picks one or gets a different recommendation with `--reshuffle`.

### `backlog diff` semantic output

Instead of raw `git diff` on JSON, shows:

```
Tasks changed since last commit:

  + t-428 Build brana CLI (added, pending)
  ~ t-424 CLI tools spike: pending → completed
  - t-099 Old unused task (removed)
  ~ t-003 Deploy: priority null → P1
```

### Scheduler data aggregation

```rust
// Combines three sources:
// 1. scheduler.json — job config (schedule, project, type, enabled)
// 2. last-status.json — last run result (status, exit_code, timestamp)
// 3. systemctl --user show — next trigger time, active state
```

### File structure

```
system/cli/
├── rust/
│   ├── Cargo.toml   # brana binary
│   ├── src/
│   │   ├── main.rs        # entry point
│   │   ├── cli.rs         # arg parsing (clap derive)
│   │   ├── files.rs       # large file manifest model + SHA-256 verification
│   │   ├── tasks.rs       # task data model
│   │   ├── query.rs       # task query/filter engine
│   │   ├── fmt.rs         # themed output formatting
│   │   ├── themes.rs      # theme loading
│   │   ├── sync.rs        # GitHub Issues sync
│   │   ├── util.rs        # shared utilities
│   │   └── commands/
│   │       ├── mod.rs     # command module registry
│   │       ├── backlog.rs # brana backlog subcommands
│   │       ├── files.rs   # brana files subcommands (list, status, add, pull, push)
│   │       ├── ops.rs     # brana ops subcommands
│   │       ├── run.rs     # brana run
│   │       ├── doctor.rs  # brana doctor
│   │       └── misc.rs    # portfolio, queue, agents, version, validate
│   └── target/release/brana  # compiled binary
├── themes.json      # canonical icon/style definitions (single source of truth)
└── aliases.sh       # shell aliases + pipeline functions
tests/test_cli.py    # e2e smoke tests
```

## Challenger findings

Reviewed 2026-03-14. Key changes incorporated:

1. **themes.json extracted** — canonical source of truth for icons/styles, loaded by both CLI and referenced by SKILL.md. Prevents drift.
2. **Duplicate task ID** (t-428) found and fixed → t-430 reassigned.
3. **Rust adopted** — Python replaced before v1 shipped. Single binary, ~12ms startup, 34x faster than Python equivalent.
4. **`ops enable/disable/run` acknowledged as write exceptions** — no Claude Code equivalent exists.
5. **`backlog focus` formula specified** — priority × staleness − effort − blocked depth.
6. **`backlog search`** added — free-text search across subjects/descriptions/contexts.
7. **`backlog diff`** redesigned — semantic diffs (added/removed/changed) instead of raw JSON diff.
8. **`backlog tree`** replaces `graph` — ASCII subtree of a phase or milestone with `--depth N` flag.
9. **`brana doctor`** includes duplicate ID check.
10. **Shell completions** — free via clap derive macros.

## System Integration Analysis

Analysis of where the CLI replaces, complements, or enables new patterns across the brana system.
Full guide: [docs/guide/cli.md](../guide/cli.md)

### Replaces (inefficient patterns → CLI)

| Current pattern | Location | CLI replacement | Impact |
|----------------|----------|-----------------|--------|
| jq task queries | session-start.sh:128-152 | `brana backlog query` (Rust) | 34x faster, 20 lines saved |
| Task filtering logic in SKILL.md prose | backlog/SKILL.md:238-241 | `brana backlog query` | Single source of truth |
| Manual scheduler.json reading | scheduler/SKILL.md | `brana ops status/health` | Structured output |
| `systemctl --user` calls in scripts | hooks, skills | `brana ops run/enable/disable` | Job name validation |
| `sync-state.sh push` in scheduler | scheduler.json | `brana ops sync` | Unified interface |
| `index-knowledge.sh` in scheduler | scheduler.json | `brana ops reindex` | Same |
| Venture detection (duplicated in 2 hooks) | session-start*.sh | `brana doctor` | Deduplication |
| Git diff + grep for drift detection | close/SKILL.md:182-207 | `brana ops drift` | Single command |
| `gh-sync.sh` calls (7 places) | backlog/SKILL.md | `brana backlog sync` | Unified sync |
| Task validation schema | post-tasks-validate.sh:34-64 | `brana doctor` (IDs) | Built-in |
| Task rollup logic | post-tasks-validate.sh:66-111 | `brana backlog rollup` | 40 lines saved |
| Session metrics computation | session-end.sh:44-97 | `brana ops metrics` | 45 lines saved |

### Complements (same view, different context)

| Brana component | CLI role |
|----------------|---------|
| `/brana:backlog status` | `bs` — same view without opening Claude Code |
| `/brana:backlog next` | `bn` — quick terminal check |
| `/brana:build` classify | `bf` (focus) — pre-decision daily pick |
| `/brana:close` drift | `bod` (ops drift) — standalone check |
| `/brana:review` health | `boh` (ops health) — scheduler subset |
| Session-start hook | `bd` (doctor) — manual health check anytime |

### Enables (new workflows)

1. **Morning routine:** `bf` → pick task → open Claude Code → `/brana:backlog start`
2. **Between-session checks:** `bo` + `boh` — scheduler healthy?
3. **Pipeline scripting:** `bfq --count --tag scheduler` in cron/CI
4. **Stale task hygiene:** `bstale --days 30` weekly
5. **Pre-commit review:** `bdiff` before committing tasks.json
6. **Dependency planning:** `bb` + `btree ph-001` for architecture conversations
7. **Cross-client overview:** `bs --all` from any terminal

## Field Notes

### 2026-03-15: CLI binary must be rebuilt after adding subcommands
After adding `brana backlog sync` in Rust source, running the command gave "unrecognized subcommand" because the installed binary was stale. `cargo build --release` fixes it (binary is symlinked, no copy needed). Consider adding a source-vs-binary staleness check.
Source: session 2026-03-15, t-475

### 2026-03-15: Batch skill metadata addition works cleanly as single chore commit
Added `argument-hint` field to 22 SKILL.md files in one batch commit + extending-skills doc update. Pattern: when adding a new metadata field to skills, do it as a dedicated chore branch touching all skills at once rather than incrementally.
Source: session 2026-03-15, chore(skills)
