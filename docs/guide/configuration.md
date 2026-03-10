# Configuration

Brana works out of the box with sensible defaults. This guide covers the settings you can customize.

## Display theme

The `/brana:backlog` skill supports display themes that control how task lists are rendered.

```
/brana:backlog theme compact
/brana:backlog theme detailed
```

Theme preferences are stored in `.claude/tasks-config.json` within each project:

```json
{
  "display": {
    "theme": "compact"
  }
}
```

Available themes:

| Theme | Description |
|-------|-------------|
| `compact` | One line per task, minimal columns |
| `detailed` | Full task info including descriptions, tags, and context |

If no theme is set, `/brana:backlog` uses the `compact` theme by default.

## Task portfolio

To see tasks across multiple projects in a single view, register projects in `~/.claude/tasks-portfolio.json`:

```json
{
  "projects": [
    {
      "name": "my-app",
      "path": "~/projects/my-app",
      "tasksFile": ".claude/tasks.json"
    },
    {
      "name": "other-project",
      "path": "~/projects/other-project",
      "tasksFile": ".claude/tasks.json"
    }
  ]
}
```

Each entry needs:

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Display name for the project |
| `path` | yes | Absolute path or `~`-prefixed path to project root |
| `tasksFile` | no | Relative path to tasks file (default: `.claude/tasks.json`) |

Once registered, `/brana:backlog` can show cross-project views when invoked with the portfolio flag.

## Scheduler

The scheduler runs recurring jobs via systemd user timers. Configuration lives in `~/.claude/scheduler/scheduler.json`.

See the dedicated [Scheduler guide](scheduler.md) for full details on job configuration, enabling/disabling jobs, and adding custom jobs.

Quick reference:

```bash
brana-scheduler status           # see all jobs and their state
brana-scheduler enable <job>     # enable a job
brana-scheduler disable <job>    # disable a job
brana-scheduler deploy           # regenerate systemd units from config
```

## Bootstrap options

`bootstrap.sh` is the installer for the identity layer. It supports three modes:

### Full sync (default)

```bash
./bootstrap.sh
```

Deploys everything: CLAUDE.md, rules, scripts, statusline, scheduler, claude-flow config, plugin registration. Idempotent -- safe to run repeatedly.

### Dry-run check

```bash
./bootstrap.sh --check
```

Shows what would change without applying anything. Reports each file as:
- `+` new (would be created)
- `~` changed (would be updated)
- `=` unchanged (already current)

### Plugin cache sync

```bash
./bootstrap.sh --sync-plugin
```

Copies the current `system/` directory to the installed plugin cache. Use this during development when you want the installed plugin to reflect local changes without a full reinstall.

## File locations

| File | Location | Purpose |
|------|----------|---------|
| Plugin manifest | `system/.claude-plugin/plugin.json` | Plugin name, version, metadata |
| Plugin hooks | `system/hooks/hooks.json` | PreToolUse, SessionStart, SessionEnd hooks |
| Global identity | `~/.claude/CLAUDE.md` | Claude's personality and principles |
| Global rules | `~/.claude/rules/*.md` | Behavioral rules loaded every session |
| Global scripts | `~/.claude/scripts/*.sh` | Helper scripts for hooks and skills |
| Settings hooks | `~/.claude/settings.json` | PostToolUse hooks (bootstrap-installed) |
| Scheduler config | `~/.claude/scheduler/scheduler.json` | Job definitions and defaults |
| Task config | `.claude/tasks-config.json` | Per-project display settings |
| Task portfolio | `~/.claude/tasks-portfolio.json` | Cross-project task registry |
| Project tasks | `.claude/tasks.json` | Per-project task list |
| Project identity | `.claude/CLAUDE.md` | Per-project conventions |

## Environment variables

Brana does not require any environment variables. claude-flow (the memory layer) uses these if present:

| Variable | Purpose |
|----------|---------|
| `CLAUDE_FLOW_DB` | Path to claude-flow SQLite database |
| `CLAUDE_PLUGIN_ROOT` | Set by Claude Code -- points to plugin directory |
