# Feature: Scheduler Hardening (Wave 1)

**Date:** 2026-02-19
**Status:** shipped
**Backlog:** #48, #49, #50

## Goal

Make brana-scheduler production-ready: validate units before deploy, notify on failure, retry transient errors. Currently failures are silent unless you check logs.

## Audience

The user (single operator) running scheduled Claude Code skills and bash commands via systemd user timers.

## Constraints

- systemd 257 (supports RestartMaxDelaySec, %N specifier)
- User services only (~/.config/systemd/user/)
- Desktop may not be available (headless/SSH sessions, overnight runs)
- Scheduler config must remain backwards-compatible
- notify-send works on X11 and Wayland but needs DISPLAY/DBUS env vars

## Scope (v1)

### #48 — Validation improvements
- `systemd-analyze calendar "$schedule"` in validate — preview next run time per job
- `systemd-analyze --user verify --recursive-errors=yes` in validate — verify deployed units (post-daemon-reload)
- Custom check: OnFailure target unit existence
- Calendar preview during deploy

### #49 — OnFailure notifications
- `brana-sched-notify@.service` template unit (Type=oneshot)
- `brana-scheduler-notify.sh` — writes `last-status.json` (primary), best-effort notify-send (secondary)
- Wire into `service.template` via `OnFailure=`
- Status line segment reads `last-status.json`

### #50 — Retry with backoff
- Retry loop in `brana-scheduler-runner.sh` (not systemd Restart=)
- Config-driven: `maxRetries` (default 0 — opt-in), `retryBackoffSec` (default 30)
- Exponential backoff: sleep N, 2N, 4N...
- Release flock between retry attempts (challenger finding)
- Remove `set -e` from runner (errors handled explicitly)

## Deferred

- #45 staleness-report.sh (separate feature, enter repo)
- #51 output-to-memory pipeline (separate feature)
- Email/webhook notifications (future — only desktop notify-send for now)
- OnSuccess notifications

## Research findings

### systemd-analyze verify
- Must use `--recursive-errors=yes` — default exits 0 even with errors
- Does NOT validate OnCalendar expressions (need `calendar` separately)
- Does NOT validate OnFailure target existence (need custom check)
- Run AFTER daemon-reload, not on raw template files

### systemd-analyze calendar
- `--iterations=N` shows next N runs
- Output is text-only, parse "Next elapse:" line
- DST transitions can cause skipped/doubled runs

### OnFailure
- `%n` passes full unit name including `.service` suffix
- notify-send needs DISPLAY + DBUS_SESSION_BUS_ADDRESS from systemd user service
- Notification unit must NOT reference itself in OnFailure (recursion)
- OnFailure fires when unit enters "failed" state (covers exit != 0, timeout, signal)

### Retry
- systemd Restart=on-failure has gotchas with Type=oneshot (conditions, rate limits)
- Runner-script retry preferred for timer-triggered oneshot services
- Must release flock between attempts to avoid blocking other jobs
- Default maxRetries=0 prevents silent behavior change on existing jobs

### Challenger findings (addressed in design)
- Lock-between-retries prevents 210s+ blockage
- `set -e` removal prevents retry loop kills
- File-based notification as primary (headless-safe)
- `last-status.json` for status line (single jq call vs N log dir scans)
- TimeoutStartSec in service template as safety net
- Verify after daemon-reload to avoid false errors

## Design

### Runner retry loop
```
for attempt in 1..maxRetries+1:
    acquire flock (non-blocking, skip if locked)
    execute job (timeout + claude/bash)
    release flock
    if success: break
    if attempt < maxRetries+1: sleep backoffSec * 2^(attempt-1)
```

### Notification flow
```
job fails (all retries exhausted)
  -> runner exits non-zero
  -> systemd triggers OnFailure=brana-sched-notify@%n.service
  -> notify script:
     1. writes to last-status.json (always works)
     2. tries notify-send (best-effort, may fail headless)
```

### last-status.json format
```json
{"job":"morning-check","status":"FAILED","exit_code":1,"timestamp":"2026-02-19T08:00:00-03:00","attempts":3}
```
Runner writes this after every run (success or failure). Status line reads it.

### Status line segment
```
📅 3✓ 1✗   (when failures exist)
📅 4✓       (all green — optional, could hide entirely)
```
