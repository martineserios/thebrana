# Scheduler

The brana scheduler runs recurring jobs using systemd user timers. It can execute shell commands or invoke Claude Code skills on a schedule.

## How it works

The scheduler has three components:

1. **`scheduler.json`** -- job definitions with schedules, timeouts, and retry config
2. **`brana-scheduler`** -- CLI tool that generates systemd units and manages jobs
3. **`brana-scheduler-runner.sh`** -- invoked by systemd per job; handles locking, retries, logging, and memory capture

When you run `brana-scheduler deploy`, it reads `scheduler.json`, generates a `.service` and `.timer` unit for each job, and enables them via `systemctl --user`. Systemd handles scheduling from there.

### Architecture

```
scheduler.json
    |
    v
brana-scheduler deploy
    |
    v
~/.config/systemd/user/
    brana-sched-<job>.timer       timer fires on schedule
    brana-sched-<job>.service     runs brana-scheduler-runner.sh <job>
    brana-sched-notify@.service   OnFailure handler for notifications
```

Each job runs as a oneshot systemd service. If a job fails, the `OnFailure` handler writes to `last-status.json` and sends a desktop notification (if available).

## Configuration

The scheduler config lives at `~/.claude/scheduler/scheduler.json`. Bootstrap creates it from the template on first run.

### Defaults

```json
{
  "version": 1,
  "defaults": {
    "model": "haiku",
    "allowedTools": "Read,Glob,Grep,WebSearch",
    "logRetention": 30,
    "timeoutSeconds": 300,
    "maxRetries": 0,
    "retryBackoffSec": 30,
    "captureOutput": true
  }
}
```

| Field | Default | Description |
|-------|---------|-------------|
| `model` | `haiku` | Claude model for skill-type jobs |
| `allowedTools` | `Read,Glob,Grep,WebSearch` | Tools available to skill jobs |
| `logRetention` | `30` | Number of log files to keep per job |
| `timeoutSeconds` | `300` | Max runtime before timeout (exit code 124) |
| `maxRetries` | `0` | Retry count on failure (0 = no retries) |
| `retryBackoffSec` | `30` | Base backoff between retries (doubles each attempt) |
| `captureOutput` | `true` | Store run summary in ruflo memory |

### Job types

**Command jobs** run a shell command:

```json
{
  "staleness-report": {
    "type": "command",
    "command": "./scripts/staleness-report.sh",
    "project": "~/enter_thebrana/thebrana",
    "schedule": "Mon *-*-* 09:00:00",
    "enabled": false
  }
}
```

**Skill jobs** invoke a Claude Code skill:

```json
{
  "weekly-review": {
    "type": "skill",
    "skill": "/weekly-review",
    "project": "~/enter_thebrana/thebrana",
    "schedule": "Fri *-*-* 17:00:00",
    "model": "sonnet",
    "allowedTools": "Read,Glob,Grep,WebSearch,WebFetch",
    "enabled": false
  }
}
```

### Job fields

| Field | Required | Description |
|-------|----------|-------------|
| `type` | yes | `command` or `skill` |
| `command` | for command type | Shell command to run |
| `skill` | for skill type | Skill name (e.g., `/weekly-review`) |
| `project` | yes | Project directory (supports `~` expansion) |
| `schedule` | yes | Systemd calendar expression (see below) |
| `enabled` | no | `true` (default) or `false` |
| `model` | no | Override default model for skill jobs |
| `allowedTools` | no | Override default tools for skill jobs |
| `timeoutSeconds` | no | Override default timeout |
| `maxRetries` | no | Override default retry count |
| `retryBackoffSec` | no | Override default backoff |
| `captureOutput` | no | Override default memory capture |
| `command_fallback` | no | Alternate command when primary exits 127 (not found). Command-type jobs only. |

### Schedule syntax

Schedules use systemd calendar expressions. Common patterns:

| Expression | Meaning |
|------------|---------|
| `Mon *-*-* 09:00:00` | Every Monday at 9am |
| `Mon..Fri *-*-* 08:00:00` | Weekdays at 8am |
| `Fri *-*-* 17:00:00` | Every Friday at 5pm |
| `*-*-01 10:00:00` | First of every month at 10am |
| `Sun *-*-* 03:00:00` | Every Sunday at 3am |
| `*-*-* 09:00:00` | Every day at 9am |

Validate a schedule with: `systemd-analyze calendar "Mon *-*-* 09:00:00"`

## Managing jobs

### Deploy (generate units from config)

```bash
brana-scheduler deploy
```

Reads `scheduler.json`, generates systemd units for each job, enables timers for enabled jobs, and disables timers for disabled jobs. Run this after editing `scheduler.json`.

### Check status

```bash
brana-scheduler status
```

Shows all jobs with their enabled state, last run time, exit status, next scheduled run, and schedule expression.

### Enable / disable a job

```bash
brana-scheduler enable weekly-review
brana-scheduler disable weekly-review
```

Updates both the systemd timer and `scheduler.json`. Changes persist across deploys.

### Run a job immediately

```bash
brana-scheduler run weekly-review
```

Runs the job via systemd (or directly if no unit exists). Check results with `brana-scheduler logs`.

### View logs

```bash
brana-scheduler logs                     # list all jobs with log counts
brana-scheduler logs weekly-review       # show last log for a job
brana-scheduler logs weekly-review -n 5  # show last 5 logs
```

Logs are stored in `~/.claude/scheduler/logs/<job>/YYYY-MM-DD-HHMMSS.log`. Each log file records the job name, type, project, model, timeout, full output, final status, and finish time.

### Validate configuration

```bash
brana-scheduler validate
```

Checks prerequisites (jq, systemctl, flock, claude CLI, loginctl linger), config syntax, project paths, calendar expressions, and deployed unit health.

### Teardown (remove all units)

```bash
brana-scheduler teardown
```

Stops all timers, removes all brana-sched systemd units, and runs daemon-reload. Config and logs are preserved.

## Adding a custom job

1. Edit `~/.claude/scheduler/scheduler.json` and add a job entry:

```json
{
  "my-custom-job": {
    "type": "command",
    "command": "./my-script.sh",
    "project": "~/projects/my-app",
    "schedule": "Mon *-*-* 09:00:00",
    "enabled": true,
    "timeoutSeconds": 120
  }
}
```

2. Deploy the updated config:

```bash
brana-scheduler deploy
```

3. Verify it is scheduled:

```bash
brana-scheduler status
```

## Concurrency and locking

The runner uses `flock` to prevent two jobs from running simultaneously in the same project. If a job tries to start while another job is already running in the same project directory, it exits with code 75 (SKIPPED) and does not retry.

Lock files are stored in `~/.claude/scheduler/locks/` and named by project directory basename.

## Retry behavior

When `maxRetries` is greater than 0, the runner retries failed jobs with exponential backoff:

- Attempt 1: immediate
- Attempt 2: wait `retryBackoffSec` seconds
- Attempt 3: wait `retryBackoffSec * 2` seconds
- And so on (backoff doubles each attempt)

Timeout (exit code 124) and lock conflicts (exit code 75) do not trigger retries.

## Log locations

| Path | Content |
|------|---------|
| `~/.claude/scheduler/logs/<job>/` | Per-run log files (timestamped) |
| `~/.claude/scheduler/last-status.json` | Latest status for each job (read by statusline) |
| `~/.claude/scheduler/locks/` | flock lock files |
| `journalctl --user -u brana-sched-<job>` | Systemd journal for a specific job |

## Notifications

When a job fails, the `OnFailure` handler (`brana-sched-notify@.service`) does two things:

1. Writes the failure to `last-status.json` with `notified: true`
2. Sends a desktop notification via `notify-send` (best-effort -- works when a desktop session is available, silently skipped on headless servers)

## Prerequisites

The scheduler requires:

- **systemd** with user session support (`systemctl --user`)
- **loginctl linger** enabled for your user (`sudo loginctl enable-linger $USER`) -- without this, timers stop when you log out
- **flock** (from util-linux) for job locking
- **jq** for config parsing (note: avoid jq reserved words like `def`, `if`, `then`, `else`, `reduce` as `--arg` variable names — they fail on jq 1.6)
- **claude CLI** (only for skill-type jobs)

Run `brana-scheduler validate` to check all prerequisites.

## Field Notes

### 2026-03-26: `set -u` and optional dependency sourcing
Scripts using `set -u` that source optional dependency loaders (e.g., `cf-env.sh`) must guard with `source file.sh 2>/dev/null || true` and use `${VAR:-}` instead of `$VAR`. Otherwise, missing ruflo on headless servers crashes the runner before the job even executes.
Source: t-672 Oracle VM scheduler fix

### 2026-03-26: `command_fallback` for missing binaries
When the Rust CLI binary isn't built (e.g., Oracle VM), the runner retries with `command_fallback` from `scheduler.json` on exit 127 (command not found). Add fallback shell scripts for any job that uses the Rust binary as primary command.
Source: t-672 Oracle VM scheduler fix

## Troubleshooting

See [Troubleshooting](troubleshooting.md) for common scheduler issues including flock failures, permission problems, and timer debugging.
