---
status: implemented
---
# macOS scheduler opt-out (t-3375, epic macos-portability t-3372)

Amends [ADR-071](../decisions/ADR-071-scheduler-thin-layer-over-systemd.md) (2026-09-30).

## Problem

The Mac is a work laptop that sleeps; unattended jobs stay on the always-on Linux host, so there is
no launchd backend. But scheduler-adjacent code assumes systemd and, on a host without it, either
errors cryptically, reports a success that scheduled nothing, or nags forever:

| Surface | Today on a host with no `systemctl` |
|---|---|
| `brana-scheduler <cmd>` | `ERROR: systemd is required` — no explanation of what to do instead |
| `brana ops run <job>` | `Failed to start brana-sched-X.service` (cryptic) |
| `brana ops enable/disable <job>` | prints "Enabled '<job>'" and **nothing is scheduled** (systemctl spawn failure is swallowed; and `.status().is_ok()` is true whenever the process merely *spawned*, even if it exited non-zero — wrong on Linux too) |
| `session-start` close-queue dead-man check | `/brana:close` queues entries for an extraction cron that does not exist here → after 3 days, **every session** warns "extraction cron dead" |
| `bootstrap.sh` | seeds a `scheduler.json` full of Linux paths and says "edit then run: brana-scheduler deploy" |

## Decision

Capability, not OS name: a host **has a scheduler backend** iff `systemctl` is on `PATH`.
One shared answer, used everywhere — `system/hooks/lib/scheduler-backend.sh` (shell) and
`ops.rs` (Rust, same wording; `tests/scripts/test-scheduler-no-systemd.sh` cross-checks them
end to end so the two implementations of one sentence cannot drift). Override:
`BRANA_SCHEDULER_BACKEND=none|systemd|auto` — `none` opts a systemd host out too.

- `sched_backend_available` → rc 0/1.
- `sched_backend_note` → the single explanatory sentence (no backend; unattended jobs run on the
  always-on host; ADR-071 amendment). Every surface prints this same wording.

## Behaviour after the change

| Surface | On a host with no backend |
|---|---|
| `brana-scheduler status` / `validate` | prints the note, **exit 0** (informational — nothing is wrong) |
| `brana-scheduler deploy/enable/disable/run/teardown` | prints the note, **exit 1** (the requested action cannot happen) |
| `brana ops run` | bails with the note |
| `brana ops enable/disable` (exit 0) | still edits `scheduler.json` (harmless, keeps the file consistent for a later sync) **but says plainly that nothing was scheduled here**; on hosts *with* systemctl, success requires a zero exit, not just a successful spawn |
| `session-start` close-queue check | on a backend-less host the message names the real situation and the manual command instead of "cron dead" |
| `bootstrap.sh` | does not seed `scheduler.json`; prints the note. Scripts/templates are still synced (harmless, keeps the tree identical) |
| `brana doctor` | unchanged — it has no scheduler checks |

Unchanged: hosts with systemd behave exactly as before, apart from the `.is_ok()` → exit-status fix.

Also fixed on the way (and again for the siblings the Gate 3 review found — `brana orbit` arm/disarm had the same
`.is_ok()` bug and now shares the tested `ops` helpers; Rust `is_pid_alive` no longer reads `/proc`, which made every
live pid look dead on macOS; desktop notifications use `osascript` on macOS with the text passed via the
environment, never spliced into the script): `ops enable/disable` used `Command::status().is_ok()`, which is true whenever
`systemctl` merely *spawned* — a non-zero exit still printed "Timer started" — and printed
"Timer stoped." on disable.

## Out of scope

- A launchd backend (see the ADR amendment for the deferred design sketch).
- Syncing the Mac's close-queue to the Linux host. Until then the Mac's extraction is manual:
  `bash ./system/cron/close-extraction.sh` (needs `agy`).

## Testing

- `tests/hooks/test-scheduler-backend.sh` — the helper, with and without a fake `systemctl` on PATH.
- `tests/scripts/test-scheduler-no-systemd.sh` — `brana-scheduler` exit codes/output on a PATH with no
  systemctl; the systemd path is unchanged.
- `tests/hooks/test-session-start.sh` — close-queue message variants.
- Rust unit tests in `ops.rs` for the PATH probe (pure function over a PATH string, no global env).
- Real macOS confirmation belongs to the CI job (t-3376) and a manual `brana ops status` on the Mac.
