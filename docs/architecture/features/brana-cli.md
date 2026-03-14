# Feature: Brana CLI — Standalone Terminal Interface

**Date:** 2026-03-14
**Status:** shipped
**Task:** t-428
**ADR:** ADR-022

## Problem

No way to check task status, scheduler health, or system state from a terminal without opening Claude Code. Ad-hoc jq chains are fragile and produce raw JSON instead of themed, readable output.

## Decision Record (frozen 2026-03-14)

> Do not modify after acceptance.

**Context:** t-424 spike evaluated CLI frameworks. Python (typer+rich) selected. Rust deferred to t-427 — no hot paths at current data volumes.

**Decision:** Build `brana` CLI with typer+rich, deeply integrated with `/brana:backlog` theme system and data model. 23 subcommands across 3 groups (tasks, sched, root). Read-only for tasks; scheduler control commands (enable/disable/run) are the exception.

**Consequences:** Terminal-native access, consistent themed output, extensible architecture, shell completions for free.

## Constraints

- Read-only for tasks — no task mutations from CLI (skills have hooks, validation, GitHub sync)
- Scheduler writes allowed — `enable`, `disable`, `run` have no skill equivalent
- Must render identically to `/brana:backlog` for overlapping views (status, next)
- Theme definitions live in `themes.json` (single source of truth for both CLI and SKILL.md)
- Runs with `uv run brana` or installed via `uv pip install -e .`

## Scope (v1)

### Launch set (ship first)

`tasks status`, `tasks next`, `tasks query`, `sched status`, `sched health`, `doctor`, `version`

### `brana tasks` — 11 subcommands

| Command | Args | Description |
|---------|------|-------------|
| `query` | `--tag`, `--status`, `--stream`, `--priority`, `--effort`, `--project` | Filter tasks with AND logic |
| `search` | `<text>` | Free-text search across subjects, descriptions, contexts |
| `status` | `[project]`, `--all`, `--wide` | Portfolio or project status (mirrors backlog status) |
| `next` | `[project]`, `--stream`, `--tag` | Next unblocked task by priority |
| `focus` | `[project]` | Smart daily pick (see ranking formula below) |
| `blocked` | `[project]` | Blocked dependency chains — what's stuck and why |
| `stale` | `--days N` (default 14) | Tasks pending > N days with no activity |
| `burndown` | `--period week\|month` | Completed vs created over time |
| `diff` | — | Semantic diff of tasks.json since last commit (added/removed/status changed) |
| `context` | `<id>` | Print task context inline |
| `graph` | `<phase-or-milestone-id>`, `--depth N` | ASCII dependency graph |

### `brana sched` — 9 subcommands

| Command | Args | Description | Read/Write |
|---------|------|-------------|------------|
| `status` | `--wide` | Dashboard: all jobs, last run, next trigger, health | Read |
| `logs` | `<job-name>`, `--tail N` | View logs for a job | Read |
| `run` | `<job-name>` | Manually trigger a job now | **Write** |
| `history` | `<job-name>`, `--last N` | Run history (pass/fail trend) | Read |
| `collisions` | — | Detect same-project schedule conflicts | Read |
| `enable` | `<job-name>` | Enable a disabled job | **Write** |
| `disable` | `<job-name>` | Disable a job | **Write** |
| `drift` | — | Compare live timers vs template config | Read |
| `health` | — | Aggregate: failures in 24h, missed runs, lock contention | Read |

### `brana` root — 2 subcommands

| Command | Description |
|---------|-------------|
| `version` | Show brana system version, plugin version, ruflo version |
| `doctor` | Health check: ruflo, systemd, tasks.json validity (incl. duplicate IDs), bootstrap |

## Research

- t-424 spike: typer + rich recommended over click, pure bash, Go/Rust
- Architecture: Python surface + bash glue. Rust deferred (t-427) — no perf bottleneck at <500KB JSON
- Rich tables + markup provide themed icons/colors matching backlog skill
- Typer subcommand composition via `app.add_typer()` per command group
- Shell completions free via `typer --install-completion`

## Design

### Data flow

```
themes.json ─────→ theme.py (load once) ──→ all rendering
tasks.json ──────→ config.py (load_tasks) ──→ tasks.py (filter/sort) ──→ theme.py (render) ──→ terminal
scheduler.json ──→ config.py (load_json) ──→ sched.py (aggregate) ──→ theme.py (render) ──→ terminal
systemctl ───────→ sched.py (subprocess) ──→ theme.py (render) ──→ terminal
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

`theme.py` loads this at runtime. SKILL.md references these definitions conceptually — "render using themes.json icons." When a theme changes, update `themes.json` and both CLI and skill pick it up.

### Task classification (shared with backlog)

```python
def classify_task(task, all_tasks):
    if task["status"] == "completed": return "done"
    if task["status"] == "in_progress": return "active"
    blocked_by = task.get("blocked_by", [])
    if blocked_by:
        completed_ids = {t["id"] for t in all_tasks if t["status"] == "completed"}
        if not all(bid in completed_ids for bid in blocked_by):
            return "blocked"
    if "parked" in (task.get("tags") or []):
        return "parked"
    return "pending"
```

### `tasks focus` ranking formula

```
score = (priority_weight * 100)       # P0=400, P1=300, P2=200, P3=100, null=50
      + (staleness_days * 2)           # older tasks get a boost
      - (effort_weight * 10)           # S=10, M=20, L=30, XL=40 — prefer quick wins
      - (blocked_depth * 50)           # tasks deep in blocked chains penalized
```

Top 3 by score shown. User picks one or gets a different recommendation with `--reshuffle`.

### `tasks diff` semantic output

Instead of raw `git diff` on JSON, shows:

```
Tasks changed since last commit:

  + t-428 Build brana CLI (added, pending)
  ~ t-424 CLI tools spike: pending → completed
  - t-099 Old unused task (removed)
  ~ t-003 Deploy: priority null → P1
```

### Scheduler data aggregation

```python
# Combines three sources:
# 1. scheduler.json — job config (schedule, project, type, enabled)
# 2. last-status.json — last run result (status, exit_code, timestamp)
# 3. systemctl --user show — next trigger time, active state
```

### File structure

```
system/cli/
├── __init__.py
├── main.py          # root app: version, doctor, --version flag
├── config.py        # paths, JSON loading, project detection, classify_task()
├── theme.py         # theme loading from themes.json, Rich styling (cached)
├── themes.json      # canonical icon/style definitions (single source of truth)
├── backlog.py       # brana backlog {11 subcommands} + Rust accelerator
├── ops.py           # brana ops {11 subcommands}
├── aliases.sh       # shell aliases + Rust pipeline functions
└── rust/
    ├── Cargo.toml   # brana-query + brana-fmt binaries
    ├── src/main.rs  # fast JSON filter (12ms, 34x faster than Python)
    └── src/fmt.rs   # themed ANSI line renderer
pyproject.toml       # entry point
tests/test_cli.py    # 46 tests (unit + e2e smoke)
```

## Challenger findings

Reviewed 2026-03-14. Key changes incorporated:

1. **themes.json extracted** — canonical source of truth for icons/styles, loaded by both CLI and referenced by SKILL.md. Prevents drift.
2. **Duplicate task ID** (t-428) found and fixed → t-430 reassigned.
3. **Rust deferred** — removed from v1 architecture table. Python is fast enough for <500KB JSON. t-427 stays as future spike.
4. **`sched enable/disable/run` acknowledged as write exceptions** — no Claude Code equivalent exists.
5. **`tasks focus` formula specified** — priority × staleness − effort − blocked depth.
6. **`tasks search`** added — free-text search across subjects/descriptions/contexts.
7. **`tasks diff`** redesigned — semantic diffs (added/removed/changed) instead of raw JSON diff.
8. **`tasks graph`** gets `--depth N` flag for large trees.
9. **`brana doctor`** includes duplicate ID check.
10. **Shell completions** — free via typer, added to v1 deliverables.

## System Integration Analysis

Analysis of where the CLI replaces, complements, or enables new patterns across the brana system.
Full guide: [docs/guide/cli.md](../guide/cli.md)

### Replaces (inefficient patterns → CLI)

| Current pattern | Location | CLI replacement | Impact |
|----------------|----------|-----------------|--------|
| jq task queries | session-start.sh:128-152 | `brana-query` (Rust) | 34x faster, 20 lines saved |
| Task filtering logic in SKILL.md prose | backlog/SKILL.md:238-241 | `brana backlog query` | Single source of truth |
| Manual scheduler.json reading | scheduler/SKILL.md | `brana ops status/health` | Structured output |
| `systemctl --user` calls in scripts | hooks, skills | `brana ops run/enable/disable` | Job name validation |
| `sync-state.sh push` in scheduler | scheduler.json | `brana ops sync` | Unified interface |
| `index-knowledge.sh` in scheduler | scheduler.json | `brana ops reindex` | Same |
| Venture detection (duplicated in 2 hooks) | session-start*.sh | `brana doctor` | Deduplication |
| Git diff + grep for drift detection | close/SKILL.md:182-207 | `brana ops drift` | Single command |
| `gh-sync.sh` calls (7 places) | backlog/SKILL.md | `brana ops sync` (future) | Unified sync |
| Task validation schema | post-tasks-validate.sh:34-64 | `brana doctor` (IDs) | Built-in |
| Task rollup logic | post-tasks-validate.sh:66-111 | Future: `brana backlog rollup` | 40 lines saved |
| Session metrics computation | session-end.sh:44-97 | Future: `brana ops metrics` | 45 lines saved |

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
6. **Dependency planning:** `bb` + `bgraph ph-001` for architecture conversations
7. **Cross-client overview:** `bs --all` from any terminal
