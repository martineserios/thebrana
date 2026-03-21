---
name: scheduler
description: Scheduled jobs.
effort: low
argument-hint: "[status|logs|enable|disable|run|validate|deploy|teardown] [job]"
group: utility
allowed-tools:
  - Bash
  - AskUserQuestion
---

# Scheduler Management

Manage scheduled brana jobs from within Claude Code. This skill wraps the `brana-scheduler` CLI.

## Available commands

Run these via Bash tool:

| Action | Command |
|--------|---------|
| Show all jobs | `brana-scheduler status` |
| Show job logs | `brana-scheduler logs <job-name>` |
| Show last N runs | `brana-scheduler logs <job-name> -n 5` |
| Enable a job | `brana-scheduler enable <job-name>` |
| Disable a job | `brana-scheduler disable <job-name>` |
| Run a job now | `brana-scheduler run <job-name>` |
| Validate config | `brana-scheduler validate` |
| Redeploy after config changes | `brana-scheduler deploy` |
| Remove all timers | `brana-scheduler teardown` |

## When invoked

1. Run `brana-scheduler status` to show current state
2. Ask the user what they want to do (view logs, toggle jobs, run something)
3. Execute the appropriate command

## Adding a new job

Guide the user to edit `~/.claude/scheduler/scheduler.json`:

```json
"my-new-job": {
  "type": "skill",
  "skill": "/skill-name",
  "project": "~/path/to/project",
  "schedule": "Mon *-*-* 09:00:00",
  "model": "haiku",
  "enabled": true
}
```

After editing, run `brana-scheduler deploy` to activate.

### Schedule syntax (systemd OnCalendar)

| Pattern | Meaning |
|---------|---------|
| `Mon *-*-* 09:00:00` | Every Monday at 9am |
| `Mon..Fri *-*-* 08:00:00` | Weekdays at 8am |
| `Fri *-*-* 17:00:00` | Every Friday at 5pm |
| `*-*-01 10:00:00` | 1st of every month at 10am |
| `*-*-* 06:00:00` | Daily at 6am |

Test with: `systemd-analyze calendar "Mon *-*-* 09:00:00"`

### Job types

- `"type": "skill"` — runs `claude -p "Execute the /skill-name skill"` in the project directory
- `"type": "command"` — runs a shell command directly in the project directory
