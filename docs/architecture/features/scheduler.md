# Feature: Scheduler

**Date:** 2026-02-18
**Status:** shipped

## Goal

Run brana skills, maintenance tasks, and custom commands at configurable frequencies without manual triggering. A thin layer over systemd timers — not a workflow engine.

## Audience

Single-user brana operator managing multiple clients (enter, thebrana, palco, somos_mirada, tinyhomes, nexeye, psilea).

## Constraints

- No custom daemon — uses OS scheduling (systemd user timers)
- Headless execution via `claude -p` (non-interactive mode)
- Per-job `--allowedTools` for permission scoping — no blanket `--dangerously-skip-permissions`
- Start simple: log files for output, backlog richer notification/summary features
- Implementation lives in `thebrana` (deploys to `~/.claude/scheduler/`)
- Bash + jq toolchain (consistent with brana's existing stack — no Python/PyYAML)
- Must work on Linux (Ubuntu/Debian). macOS support deferred (launchd differs from systemd)
- Requires `loginctl enable-linger` for timers to fire after logout

## Scope (v1)

### Config file
- `~/.claude/scheduler.json` — job definitions (JSON, parseable with jq — consistent with brana's bash+jq toolchain)
- Each job: name, type (skill | command), project path, cron expression, enabled flag, allowedTools, model, timeout
- Ships with example jobs, no preset bundles (let real usage patterns emerge first)

### Deploy tool (`brana-scheduler` — bash script)
- `brana-scheduler deploy` — reads config, generates systemd timer units, ensures linger enabled
- `brana-scheduler status` — shows all jobs, last run time, exit status, next scheduled run
- `brana-scheduler logs [job-name]` — tail job logs
- `brana-scheduler enable|disable [job-name]` — toggle without removing
- `brana-scheduler run [job-name]` — manual trigger (same as scheduled, for testing)
- `brana-scheduler teardown` — stop all timers, remove systemd units

### Runner (`brana-scheduler-runner.sh`)
- Wrapper invoked by systemd per job
- Acquires lockfile (`flock`) per project to prevent concurrent execution
- Sets up environment (project CWD)
- For skill jobs: uses natural language prompt to `claude -p` (see "Skill invocation" below)
- For command jobs: runs the command directly
- Per-job timeout via `timeout` command wrapper
- Captures output to `~/.claude/scheduler/logs/{job-name}/{YYYY-MM-DD-HHMMSS}.log`
- Prunes logs beyond retention count
- Exits with appropriate code for systemd to track success/failure

### Management skill
- `/brana:scheduler` — view status, toggle jobs from within Claude Code
- Thin wrapper over `brana-scheduler` CLI

### Skill invocation

**VALIDATED.** Manual test confirmed skills load and invoke in headless `claude -p` mode:
```bash
cd ~/enter_thebrana/enter && claude -p "Execute /pattern-recall for scheduling" --model haiku
# Result: skill activated, searched memory, asked follow-up questions. Working as expected.
```

Runner uses natural language prompts: `claude -p "Execute the /morning daily operational check for this project"`. Claude recognizes the skill name from loaded descriptions and auto-invokes it. No `--system-prompt` injection needed.

## Deferred

- **Preset bundles** — brana-maintenance and business-ops job collections (ship after real usage patterns emerge)
- **Crontab fallback** — for systems without systemd. Current system is Ubuntu with systemd; second backend would bitrot.
- **Output to claude-flow memory** — store run summaries so `/morning` or session-start surfaces what ran overnight
- **Desktop notifications** — notify-send on completion/failure
- **Retry with backoff** — for transient failures (API rate limits, network)
- **macOS support** — launchd plist generation instead of systemd
- **Job dependencies** — "run B after A completes successfully"
- **Token budget per job** — `--max-turns` flag or token counting
- **Web dashboard** — status page (n8n-style) for monitoring
- **Slack/email alerts** — on failure or important findings
- **Worktree-based isolation** — persistent worktrees per project. Deferred because: creates stale state, contradicts git discipline (short-lived worktrees), no commit strategy for accumulated writes. Revisit if lockfile approach proves too limiting.

## Research findings

### Execution mechanism (doc 09, [doc 21](../dimensions/21-anthropic-engineering-deep-dive.md))
- `claude -p "prompt"` is the headless mode — non-interactive, suitable for cron
- `--allowedTools "Read,Glob,Grep,WebSearch"` scopes permissions per invocation
- `--output-format json` or `stream-json` for structured output
- Fan-out pattern: loop + `claude -p` works for batch processing

### Prior decisions
- Backlog #33 (n8n/Windmill): deferred — overkill for current needs
- Backlog #21 (Agent SDK headless): closed — SDK not mature enough
- [Doc 32](../reflections/32-lifecycle.md) #8 (background learning): blocked on daemon reliability — this scheduler avoids that by NOT being a daemon

### Existing infrastructure
- Session hooks already handle session-start/end lifecycle
- 31 skills ready for headless invocation
- claude-flow memory available for state persistence
- [Doc 25](../25-self-documentation.md) already designed weekly checks (staleness, links, frontmatter) — just not automated

## Resolved questions

1. **Model per job** — Yes. Default `haiku` for cheap recurring checks. Jobs override to `sonnet`/`opus` for deep reviews.
2. **Token budget** — Deferred to v2. `--allowedTools` scoping limits blast radius for now.
3. **Session isolation** — Scheduled jobs run in persistent worktrees (`../enter-scheduler/`, `../thebrana-scheduler/`). Zero conflict with interactive sessions.
4. **Log rotation** — Keep last 30 runs per job, count-based pruning after each run.

## Design

### Architecture

```
scheduler.json ──→ brana-scheduler deploy ──→ systemd timer units
                                                    │
                                          (on schedule)
                                                    ↓
                                          brana-scheduler-runner.sh
                                                    │
                                          flock (per-project lock)
                                                    │
                                          ┌─────────┴─────────┐
                                          │                   │
                                    skill jobs          command jobs
                                          │                   │
                                   claude -p "prompt"    bash command
                                          │                   │
                                          └─────────┬─────────┘
                                                    ↓
                                    timeout → log → prune → exit code
```

### Components (implemented in thebrana)

```
thebrana/system/scheduler/
├── brana-scheduler              # CLI (bash) — deploy/status/logs/enable/disable/run
├── brana-scheduler-runner.sh    # Runner (bash) — invoked by systemd per job
├── scheduler.template.json      # Default config template with example jobs
└── templates/
    ├── service.template         # systemd .service unit template
    └── timer.template           # systemd .timer unit template

thebrana/system/skills/scheduler/
└── SKILL.md                     # /brana:scheduler skill for in-session management
```

### Deploy target

```
~/.claude/scheduler/
├── scheduler.json               # User's config (from template, editable)
├── brana-scheduler              # CLI tool (symlink)
├── brana-scheduler-runner.sh    # Runner script (symlink)
├── locks/                       # flock lockfiles per project
└── logs/
    └── {job-name}/
        └── {YYYY-MM-DD-HHMMSS}.log

~/.config/systemd/user/
├── brana-sched-{job}.service    # Generated per enabled job
└── brana-sched-{job}.timer      # Generated per enabled job
```

### Config schema

```json
{
  "version": 1,
  "defaults": {
    "model": "haiku",
    "allowedTools": "Read,Glob,Grep,WebSearch",
    "logRetention": 30,
    "timeoutSeconds": 300
  },
  "jobs": {
    "staleness-report": {
      "type": "command",
      "command": "./scripts/staleness-report.sh",
      "project": "~/enter_thebrana/enter",
      "schedule": "Mon *-*-* 09:00:00",
      "enabled": true
    },
    "link-check": {
      "type": "command",
      "command": "lychee --config .lychee.toml *.md",
      "project": "~/enter_thebrana/enter",
      "schedule": "Mon *-*-* 09:00:00",
      "enabled": true
    },
    "knowledge-review": {
      "type": "skill",
      "skill": "/knowledge-review",
      "project": "~/enter_thebrana/enter",
      "schedule": "*-*-01 10:00:00",
      "model": "sonnet",
      "allowedTools": "Read,Glob,Grep,WebSearch,WebFetch",
      "enabled": true
    },
    "frontmatter-validate": {
      "type": "command",
      "command": "python3 scripts/validate-frontmatter.py",
      "project": "~/enter_thebrana/enter",
      "schedule": "Mon *-*-* 09:00:00",
      "enabled": true
    },
    "morning-check": {
      "type": "skill",
      "skill": "/morning",
      "project": "~/enter_thebrana/clients/somos_mirada",
      "schedule": "Mon..Fri *-*-* 08:00:00",
      "model": "haiku",
      "enabled": false
    },
    "weekly-review": {
      "type": "skill",
      "skill": "/weekly-review",
      "project": "~/enter_thebrana/enter",
      "schedule": "Fri *-*-* 17:00:00",
      "model": "sonnet",
      "enabled": false
    },
    "monthly-close": {
      "type": "skill",
      "skill": "/monthly-close",
      "project": "~/enter_thebrana/enter",
      "schedule": "*-*~1 10:00:00",
      "model": "sonnet",
      "allowedTools": "Read,Glob,Grep,WebSearch,WebFetch,Edit,Write",
      "timeoutSeconds": 600,
      "enabled": false
    }
  }
}
```

**Notes on config:**
- Uses systemd OnCalendar syntax directly (no cron-to-OnCalendar conversion needed)
- `*-*~1` = last day of month. `Mon..Fri` = weekdays. See `man systemd.time`.
- JSON instead of YAML — parsed with `jq`, no extra dependencies

### Runner logic (brana-scheduler-runner.sh)

```
1. Read job name from $1
2. Parse config with jq: extract type, project, command/skill, model, allowedTools, timeout
3. Resolve project path (expand ~)
4. Acquire flock on ~/.claude/scheduler/locks/{project-slug}.lock (skip if locked)
5. cd to project directory
6. Set up log file: ~/.claude/scheduler/logs/{job}/{YYYY-MM-DD-HHMMSS}.log
7. Based on type:
   - skill: timeout $TIMEOUT claude -p "Execute the $SKILL skill for this project" \
            --model $MODEL --allowedTools "$TOOLS" >> "$LOGFILE" 2>&1
   - command: timeout $TIMEOUT eval "$COMMAND" >> "$LOGFILE" 2>&1
8. Capture exit code (124 = timeout, distinguish from job failure)
9. Prune logs: keep last $RETENTION, delete older
10. Release lock, exit with job's exit code
```

### CLI commands (brana-scheduler — bash script)

| Command | What it does |
|---------|-------------|
| `deploy` | Read config → verify linger enabled → generate systemd units → enable timers → daemon-reload |
| `status` | `systemctl --user list-timers 'brana-sched-*'` + last exit status from journal |
| `logs [job] [-n N]` | Show last N log entries for a job (default: tail last run) |
| `enable [job]` | `systemctl --user enable --now brana-sched-{job}.timer` |
| `disable [job]` | `systemctl --user disable --now brana-sched-{job}.timer` |
| `run [job]` | `systemctl --user start brana-sched-{job}.service` (immediate one-shot) |
| `teardown` | Stop all timers, remove units, daemon-reload |
| `validate` | Check config syntax, verify paths exist, check linger status |

### systemd unit templates

**service.template:**
```ini
[Unit]
Description=brana scheduler: %i

[Service]
Type=oneshot
ExecStart=%h/.claude/scheduler/brana-scheduler-runner.sh %i
Environment=HOME=%h
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
```

**timer.template:**
```ini
[Unit]
Description=brana scheduler timer: %i

[Timer]
OnCalendar={{SCHEDULE}}
Persistent=true

[Install]
WantedBy=timers.target
```

`Persistent=true` catches up on missed runs (machine off, sleep). Matches APScheduler's `misfire_grace_time` pattern from Palco.

### /brana:scheduler skill

Thin in-session wrapper:
- `Show status of all scheduled jobs` → `brana-scheduler status`
- `Enable/disable a job` → `brana-scheduler enable/disable`
- `Show recent logs` → `brana-scheduler logs`
- `Run a job now` → `brana-scheduler run`
- `Add a new job` → guides user through config JSON edit + deploy

### Concurrency control

- `flock` lockfile per project (`~/.claude/scheduler/locks/{project}.lock`)
- If lock is held (another scheduled job running in same project), skip with exit code 75 (TEMPFAIL)
- Does NOT block interactive Claude Code sessions — they're separate processes, read operations don't conflict
- Default `allowedTools` is read-only, minimizing write conflict risk

### Challenger review resolutions

| Finding | Resolution |
|---------|-----------|
| `claude -p "/skill"` untested | Design two approaches: natural language prompt (primary) + embedded skill content (fallback). **Requires manual validation before building.** |
| Persistent worktrees create stale state | Dropped from v1. Jobs run in project directory directly. Lockfile prevents concurrent scheduled access. |
| `loginctl enable-linger` required | `brana-scheduler deploy` checks and enables linger. `validate` command checks it. |
| No token budget | Added per-job `timeoutSeconds` with `timeout` command wrapper. Token budget deferred. |
| Concurrent execution | `flock` lockfile per project. Skip if locked. |
| PyYAML unnecessary | Switched to JSON + jq. Pure bash toolchain. |
| Crontab fallback bitrot | Dropped from v1. systemd-only. |
| Preset bundles premature | Dropped from v1. Ship example jobs in template, user customizes. |

### Cross-project patterns (from Palco)

Transferable patterns from Palco's APScheduler implementation (ADR-010):
- `Persistent=true` ↔ `misfire_grace_time`: catch up on missed runs
- `flock` ↔ `max_instances=1`: prevent duplicate execution
- systemd journal ↔ `webhook_events` table: audit trail per job
- `brana-scheduler deploy` sync ↔ startup sync pattern: re-create state on config change

### ADR

See [ADR-002](../decisions/ADR-002-scheduler-thin-layer-over-systemd.md)

## Tasks

Implementation lives in `thebrana` repo. Deploy target: `~/.claude/scheduler/`.

| # | Task | Depends On | Acceptance Criteria |
|---|------|-----------|-------------------|
| 1 | Create scheduler directory structure in thebrana | — | `thebrana/system/scheduler/` with runner, CLI, templates, example config |
| 2 | Implement `brana-scheduler-runner.sh` | — | Runner parses config with jq, acquires flock, runs skill/command jobs, logs output, prunes old logs, applies timeout |
| 3 | Implement systemd unit templates | — | `service.template` and `timer.template` with correct variable substitution |
| 4 | Implement `brana-scheduler` CLI | #2, #3 | `deploy`, `status`, `logs`, `enable`, `disable`, `run`, `validate`, `teardown` all working. Checks linger on deploy. |
| 5 | Create example `scheduler.template.json` | — | Template with commented example jobs (staleness-report, knowledge-review, morning-check) |
| 6 | Create `/brana:scheduler` skill | #4 | Skill wraps CLI commands, provides in-session management |
| 7 | Update `deploy.sh` to install scheduler | #1-#5 | Scheduler files deployed to `~/.claude/scheduler/`, template copied if config doesn't exist |
| 8 | End-to-end test: deploy + run + verify | #4, #7 | Manual test: deploy a command job, run it, verify log output and systemd timer |

## Open questions

None remaining. All critical questions resolved.
