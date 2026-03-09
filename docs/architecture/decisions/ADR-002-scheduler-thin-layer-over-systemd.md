# ADR-002: Scheduler — thin layer over systemd timers

**Date:** 2026-02-18
**Status:** accepted (hardened 2026-02-19)

## Context

Brana has ~15 recurring tasks that should run at regular intervals (daily/weekly/monthly) but currently require manual invocation:

- **Weekly**: staleness reports, link checks, dependency freshness, frontmatter validation
- **Monthly**: knowledge reviews, growth checks, monthly financial close
- **Daily**: morning focus cards for venture clients
- **On-demand**: arbitrary commands and scripts

These tasks are well-defined (doc 25 designed the weekly checks, [doc 34](../dimensions/34-venture-operating-system.md) designed the business cadence) but none are automated. The user must remember to trigger each one. Backlog items #33 (n8n/Windmill) and #21 (Agent SDK for cron) were deferred — external platforms are overkill, the SDK isn't mature.

The execution mechanism exists: `claude -p "prompt"` runs Claude Code headlessly with `--allowedTools` for permission scoping and `--model` for cost control.

## Decision

Build a thin scheduling layer with three components:

1. **Config file** (`~/.claude/scheduler.json`) — JSON job definitions with systemd OnCalendar schedules, tool permissions, model selection, and project paths. JSON chosen over YAML for jq compatibility — no extra dependencies.

2. **CLI tool** (`brana-scheduler`) — Bash script that reads the config with `jq` and manages systemd timer units. Commands: `deploy`, `status`, `logs`, `enable`, `disable`, `run`, `validate`, `teardown`.

3. **Runner script** (`brana-scheduler-runner.sh`) — Bash wrapper invoked by systemd per job. Acquires per-project lockfile, sets up project CWD, calls `claude -p` with the right flags (for skill jobs) or runs commands directly, captures output to log files, applies per-job timeout, prunes old logs. Post-hardening additions: retry loop with exponential backoff (configurable `maxRetries`/`retryBackoffSec`, flock release between attempts), `last-status.json` atomic writes for statusline health, and output-to-memory pipeline (`captureOutput` stores run summaries in claude-flow memory).

4. **Notification unit** (`brana-sched-notify@.service`) — systemd template unit triggered via `OnFailure=`. Writes failure to `last-status.json` (primary, headless-safe) and attempts `notify-send` (secondary, desktop). No OnFailure on itself (recursion guard).

A `/brana:scheduler` skill provides in-session management as a thin wrapper over the CLI.

### Why systemd timers (only, no crontab fallback):
- `journalctl --user -u brana-sched-{job}` for built-in logging
- `systemctl --user list-timers` shows next-run and last-run at a glance
- `Persistent=true` catches up on missed runs (machine was off/asleep)
- Enable/disable per unit without editing a monolithic crontab
- A crontab fallback would create a second code path that bitrot (current system is Ubuntu with systemd)

### Why bash + jq (not Python + PyYAML):
- Brana is a bash-native system (hooks, runner scripts, deploy.sh all bash)
- `jq` is already a dependency (used in every hook)
- JSON parsing is reliable with `jq`; YAML parsing in bash is fragile
- No additional dependencies to install or manage
- Simpler deployment (copy scripts, not manage Python packages)

### Why NOT a custom daemon:
- Daemons need process supervision, crash recovery, PID management
- [Doc 05](../dimensions/05-claude-flow-v3-analysis.md) flagged claude-flow daemon stability as a concern
- systemd already IS the process supervisor — reuse it
- A config file + deploy script is ~200 lines; a daemon is ~2000+

### Why NOT n8n/Windmill:
- Another service to install, update, secure, and keep running
- Visual workflow editor is irrelevant for `claude -p` one-liners
- Adds infrastructure complexity for zero functional gain at current scale

### Why NOT persistent worktrees:
- Initial design proposed persistent worktrees for session isolation
- Challenger review identified: worktrees create stale state, accumulate untracked writes, contradict git discipline (short-lived worktrees), have no commit strategy
- Resolution: jobs run in the project directory directly with `flock` per-project lockfile
- Interactive Claude Code sessions are not blocked — they're separate processes, read operations don't conflict
- Default `allowedTools` is read-only, minimizing write conflict risk

## Consequences

### Becomes easier
- Recurring tasks run automatically — no manual memory required
- Adding a new scheduled task: add a JSON block to config, run `brana-scheduler deploy`
- Debugging: `journalctl --user -u brana-sched-{job}` shows full history
- Cost control: `model: haiku` for cheap recurring checks, `sonnet`/`opus` for deep reviews
- Per-job timeout prevents runaway execution
- Transient failures self-heal via retry with backoff (opt-in, `maxRetries` default 0)
- Failures surface via desktop notifications and statusline health segment (`📅 3✓ 1✗`)
- `brana-scheduler validate` catches silent OnCalendar typos and missing units before they cause silent failures
- `/morning` and session-start can query scheduler run history via claude-flow memory search

### Becomes harder
- systemd user services require `loginctl enable-linger $USER` to run without login session
- Users must learn systemd OnCalendar syntax (different from cron, but well-documented)
- Testing scheduled jobs requires either waiting or `brana-scheduler run`
- macOS users need a launchd backend (deferred)

### New dependencies
- `jq` — for JSON config parsing (already used by hooks)
- systemd user services enabled — `systemctl --user` must work
- `loginctl enable-linger` — required for timers after logout
- `claude` CLI on PATH — headless mode must be available
- `flock` — for concurrency control (part of util-linux, always present)
- `claude-flow` CLI — for output-to-memory pipeline (graceful degradation if unavailable)
- `notify-send` — for desktop failure notifications (graceful degradation if headless)

### Risks
- **API cost**: unattended jobs consume tokens. Mitigated by `model: haiku` default, explicit `allowedTools` scoping, and per-job timeout.
- **Stale config**: user edits JSON but forgets `brana-scheduler deploy`. Mitigated by `validate` command; future: session-start hook that warns on config-newer-than-last-deploy.
- **Skill invocation in headless mode**: VALIDATED — `claude -p "Execute /pattern-recall for scheduling"` successfully loaded and invoked the skill. Natural language prompts work.
- **Concurrent access**: `flock` prevents concurrent scheduled jobs per project. Interactive sessions are not locked (separate process, read-only default).
