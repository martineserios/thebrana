#!/usr/bin/env bash
# scheduler-backend.sh — does this host have a scheduler backend? (t-3375, ADR-071 amendment)
#
# Explicit override, checked first: BRANA_SCHEDULER_BACKEND=none opts a host out even if it has
# systemd; =systemd forces "present" (tests); =auto or anything else probes.
#
# Capability, not OS name: the scheduler is systemd-only, so a host has a backend iff `systemctl`
# is an executable on PATH. macOS (a sleeping work laptop) has none by decision — unattended jobs
# run on the always-on Linux host. Every scheduler-adjacent surface (brana-scheduler, brana ops,
# session-start, bootstrap) asks this one function and prints this one sentence.
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/scheduler-backend.sh"
#   sched_backend_available || echo "$(sched_backend_note)"

# Explicit PATH walk with -x: bash's `command -v` also reports a NON-executable file as found.
sched_backend_available() {
    case "${BRANA_SCHEDULER_BACKEND:-auto}" in
        none)    return 1 ;;
        systemd) return 0 ;;
    esac
    local d IFS=:
    for d in $PATH; do
        [ -n "$d" ] || d=.
        [ -f "$d/systemctl" ] && [ -x "$d/systemctl" ] && return 0
    done
    return 1
}

# The session-start close-queue warning for a host with no scheduler (kept here, not in the hook,
# to keep session-start.sh under the 50KB file-size gate). $1 = number of stale entries.
sched_closequeue_nag() {
    printf '%s\n' "⚠ [Close queue] $1 entr(ies) unprocessed >3 days — this host has no scheduler, so nothing extracts them here (unattended jobs run on the always-on host). Extract manually from the thebrana checkout: ./system/cron/close-extraction.sh (needs agy), or ignore."
}

sched_backend_note() {
    local why="systemctl not found"
    [ "${BRANA_SCHEDULER_BACKEND:-}" = none ] && why="opted out via BRANA_SCHEDULER_BACKEND=none"
    printf '%s\n' "no scheduler backend on this host ($why): unattended jobs run on the always-on host, not here — see ADR-071 amendment."
}
