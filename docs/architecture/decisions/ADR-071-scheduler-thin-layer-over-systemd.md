---
informs:
  - docs/architecture/decisions/ADR-015-state-consolidation-plugin-first.md
status: accepted
---

# ADR-071: Scheduler — thin layer over systemd timers

**Date:** 2026-02-18
**Status:** accepted (hardened 2026-02-19; amended 2026-09-30 — launchd deferred by decision, see Amendment)

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

3. **Runner script** (`brana-scheduler-runner.sh`) — Bash wrapper invoked by systemd per job. Acquires per-project lockfile, sets up project CWD, calls `claude -p` with the right flags (for skill jobs) or runs commands directly, captures output to log files, applies per-job timeout, prunes old logs. Post-hardening additions: retry loop with exponential backoff (configurable `maxRetries`/`retryBackoffSec`, flock release between attempts), `last-status.json` atomic writes for statusline health, and output-to-memory pipeline (`captureOutput` stores run summaries in ruflo memory).

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
- [Doc 05](../dimensions/05-claude-flow-v3-analysis.md) flagged ruflo daemon stability as a concern
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
- `/morning` and session-start can query scheduler run history via ruflo memory search

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
- `ruflo` CLI — for output-to-memory pipeline (graceful degradation if unavailable)
- `notify-send` — for desktop failure notifications (graceful degradation if headless)

### Risks
- **API cost**: unattended jobs consume tokens. Mitigated by `model: haiku` default, explicit `allowedTools` scoping, and per-job timeout.
- **Stale config**: user edits JSON but forgets `brana-scheduler deploy`. Mitigated by `validate` command; future: session-start hook that warns on config-newer-than-last-deploy.
- **Skill invocation in headless mode**: VALIDATED — `claude -p "Execute /pattern-recall for scheduling"` successfully loaded and invoked the skill. Natural language prompts work.
- **Concurrent access**: `flock` prevents concurrent scheduled jobs per project. Interactive sessions are not locked (separate process, read-only default).

## Amendment 2026-09-30 — no launchd backend; hosts without systemd opt out (t-3375)

**Decision.** The scheduler stays systemd-only. A launchd backend, listed above as "deferred", is
**deferred by decision**, not by neglect: the Mac is a work laptop that sleeps, and unattended jobs
stay on the always-on Linux host (owner's call, 2026-09-30). A scheduler on a machine that is asleep
half the day would run jobs late or not at all and add a second code path — the exact bitrot the
"no crontab fallback" argument above rejects.

**Consequence — degrade, don't fail.** Every scheduler-adjacent surface must behave sensibly on a
host with no `systemctl` instead of erroring cryptically or reporting a success that scheduled
nothing. Detection is capability-based (`systemctl` on PATH), not `uname`. Behaviour matrix and
tests: [macos-scheduler-optout](../features/macos-scheduler-optout.md).

**Deferred design sketch (so it is not re-derived if a Mac ever needs unattended jobs).**
- *Backend:* per-user **LaunchAgent** (`~/Library/LaunchAgents/`, `launchctl bootstrap gui/$UID`) — not a
  LaunchDaemon (needs sudo, wrong blast radius). Runs only while the user is logged in (the analogue
  of no `enable-linger`).
- *Schedule:* keep `OnCalendar` as the one config dialect and translate to `StartCalendarInterval`
  arrays. A **omitted key is a wildcard** in launchd, so `*:0/15` → four `{Minute}` dicts and `0/4:20`
  → six `{Hour,Minute}` dicts (not 24×). Weekday `Sun` = 0/7. The 28 template jobs use only: fixed
  times, weekday lists, comma hour lists and `a/b` steps. The translator must **fail loudly** on any
  other form; a silently wrong schedule is worse than none. Pure text → unit-testable on Linux.
- *Persistent=true:* launchd fires one coalesced missed run at wake, but nothing if the machine was
  fully off — document, don't emulate.
- *No `OnFailure=` / `journalctl`:* the plist `ProgramArguments` wraps runner + `brana-scheduler-notify.sh`
  (`osascript` instead of `notify-send`); logs are the runner's own files.
- *Rust side:* `ops.rs` should delegate to the bash CLI rather than call the init system itself, so
  backend dispatch lives in one place.

