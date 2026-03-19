# ADR-022: Brana CLI — Standalone Terminal Interface

**Date:** 2026-03-14
**Status:** superseded (implementation diverged — see What Changed)
**Related:** ADR-003 (agent execution), t-424 (spike), t-426 (scheduler viz), t-427 (Rust evaluation), t-428 (implementation)

## Context

Brana's operational tools are currently accessible only through:
1. **Claude Code plugin** — `/brana:backlog status`, `/brana:build`, etc. (requires an active Claude session)
2. **Raw scripts** — `jq` pipelines on tasks.json, `systemctl --user` for scheduler, manual log hunting

This creates two gaps:
- **No terminal-native access.** Checking task status or scheduler health requires opening Claude Code. A quick `brana tasks next` from any terminal should be possible.
- **Script fragility.** Ad-hoc `jq` chains break silently, have no error handling, and can't render themed output.

The t-424 spike evaluated CLI frameworks and concluded with a hybrid architecture decision.

## Decision

Build a standalone CLI (`brana`) using **Python (typer + rich)** as the primary surface.

### Architecture: Python + Bash (Rust deferred to t-427)

| Layer | Language | Role | Examples |
|-------|----------|------|----------|
| **CLI surface** | Python (typer) | Subcommand dispatch, arg parsing, interactive prompts | `brana backlog query`, `brana ops status` |
| **Rendering** | Python (rich) | Themed terminal output — tables, trees, progress bars | Theme system via `themes.json` |
| **Glue** | Bash (existing) | Bootstrap, scheduler runner, cf-env — stays untouched | `bootstrap.sh`, `brana-scheduler-runner.sh` |

> **Note:** Rust hot-path binaries were considered (t-427) but deferred. Tasks.json is <500KB — Python parsing is fast enough. If profiling later reveals bottlenecks, Rust can be added surgically without architectural changes.

### Command groups

```
brana backlog {query,search,status,next,focus,blocked,stale,burndown,diff,context,graph}
brana ops {status,logs,run,history,collisions,enable,disable,drift,health,sync,reindex}
brana version
brana doctor
brana --version
```

**v1 launch set** (ship first, expand later): `backlog status`, `backlog next`, `backlog query`, `ops status`, `ops health`, `doctor`, `version`.

**Scheduler writes exception:** `ops enable`, `ops disable`, and `ops run` mutate system state (systemd units, job execution). These are explicitly allowed because managing systemd from inside Claude Code is awkward and there is no skill equivalent.

**Bash wrappers:** `ops sync` wraps `sync-state.sh`, `ops reindex` wraps `index-knowledge.sh`.

**Shell aliases:** `system/cli/aliases.sh` provides shortcuts: `bq` (backlog query), `bo` (ops status), `bf` (backlog focus), etc.

### Deep backlog integration

The CLI shares the same data model and rendering logic as `/brana:backlog`:
- **Same theme system** — reads `~/.claude/tasks-config.json`, renders with classic/emoji/minimal icons
- **Same data sources** — `.claude/tasks.json`, `~/.claude/tasks-portfolio.json`
- **Same filtering logic** — status classification, blocked_by resolution, priority sorting
- **Same display conventions** — task-line template, tree connectors, wide mode

The CLI is a read-only terminal mirror of `/brana:backlog`. Writes still go through the skill (which has hooks, validation, GitHub sync).

### Entry point

```toml
[project.scripts]
brana = "system.cli.main:app"
```

Installed via `uv pip install -e .` in the thebrana repo, or `uv run brana` for dev.

## Consequences

- **Positive:** Terminal-native access to tasks and scheduler without Claude Code session
- **Positive:** Themed output reuses existing backlog rendering conventions — one visual language
- **Positive:** Python gives fast iteration; Rust can be added later if profiling justifies (t-427)
- **Positive:** `brana doctor` provides system health checks (ruflo, systemd, tasks.json validity, duplicate IDs)
- **Positive:** Shell completions via `typer --install-completion` for free
- **Negative:** New dependency (typer, rich) in the system — but both are mature, well-maintained
- **Negative:** Read-only constraint means most write operations still require Claude Code (exception: sched enable/disable/run)
- **Risk (mitigated):** Theme rendering could drift between SKILL.md and Python. Fix: canonical `system/cli/themes.json` is the single source of truth. SKILL.md references it; `theme.py` loads it at runtime.

## File structure

```
system/cli/
├── __init__.py
├── main.py          # root app: version, doctor, --version flag
├── config.py        # paths, JSON loading, project detection
├── theme.py         # theme loading from themes.json, Rich styling (cached)
├── themes.json      # canonical icon/style definitions (single source of truth)
├── backlog.py       # brana backlog {11 subcommands}
├── ops.py           # brana ops {11 subcommands}
├── aliases.sh       # shell aliases (bq, bo, bf, etc.)
└── rust/            # future Rust hot-path binaries (t-427)
    └── README.md    # candidates: brana-query, brana-fmt
pyproject.toml       # entry point
tests/test_cli.py    # 34+ tests
```

## What Changed (2026-03-14 → 2026-03-18)

The original decision chose Python (typer + rich) as the CLI surface with Rust deferred. During implementation, the full CLI was built in Rust instead:

- **2026-03-14:** Rust CLI replaced Python entirely (t-428). Single binary, 12ms startup. The "Rust deferred" note in the original decision was superseded by performance results.
- **2026-03-16:** Added mission control commands: `run`, `queue`, `agents` (t-525).
- **2026-03-18:** Modular refactor (t-568): `cli.rs` split into `cli.rs` (clap structs) + `commands/` (handlers) + `util.rs` (helpers).
- **2026-03-18:** Added `brana files` subcommand for large file tracking (t-574).

**Current command surface:** 11 root commands, 19 backlog subcommands, 12 ops subcommands, 5 files subcommands. See `docs/guide/cli.md` for the authoritative reference.

**Current architecture:** Pure Rust. No Python dependency. Modules: `main.rs`, `cli.rs`, `commands/`, `tasks.rs`, `files.rs`, `transcribe.rs`, `sync.rs`, `themes.rs`, `util.rs`.
