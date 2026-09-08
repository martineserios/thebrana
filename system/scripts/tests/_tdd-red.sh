#!/usr/bin/env bash
# _tdd-red.sh — the intentionally-RED test convention (t-3323, ADR-094; generalised by t-3331).
#
# A TDD-first suite is written BEFORE the code it specifies. Until that code lands the
# suite must stay visibly RED when a human runs it, yet must not block ships through the
# validate.sh / CI sweeps that run every suite. This helper is the single seam for that:
#
#   TDD_RED_UNTIL=t-NNNN                     # the task whose landing turns the suite green
#   source "$(dirname "$0")/_tdd-red.sh"      # after the marker, before any check
#   ...checks accumulate $FAIL...
#   tdd_red_exit "$FAIL"                      # ALWAYS the last line
#
# Behaviour of tdd_red_exit:
#   FAIL == 0                         → prints GREEN and exits 0. If TDD_RED_UNTIL is still
#                                       set, also prints a STALE-MARKER line: the marker must
#                                       be deleted so the suite gates for real.
#   FAIL  > 0, BRANA_TDD_SWEEP unset  → exits 1 (a human ran it: RED is RED).
#   FAIL  > 0, BRANA_TDD_SWEEP=1      → prints "RED as expected (pending t-NNNN)", exits 0.
#                                       validate.sh Check 75 and the CI shim set the variable.
#
# validate.sh Check 75 additionally fails when a marker names a task whose status is
# `completed` — the forcing function that keeps a gutted or forgotten RED suite from
# passing forever (challenger finding, 2026-09-08).
#
# Sourced, not executed. Never `exit` from here except inside tdd_red_exit.

[ -n "${TDD_RED_UNTIL:-}" ] && echo "TDD-RED-MARKER: ${TDD_RED_UNTIL}"

tdd_red_exit() {
    local fail="${1:-0}"
    if [ "$fail" -eq 0 ]; then
        if [ -n "${TDD_RED_UNTIL:-}" ]; then
            echo "GREEN — STALE-MARKER: TDD_RED_UNTIL=${TDD_RED_UNTIL} is still set; delete the marker so this suite gates for real"
        else
            echo "GREEN"
        fi
        exit 0
    fi
    if [ "${BRANA_TDD_SWEEP:-}" = "1" ] && [ -n "${TDD_RED_UNTIL:-}" ]; then
        echo "RED as expected (pending ${TDD_RED_UNTIL}) — ${fail} failing check(s) not counted against the sweep"
        exit 0
    fi
    exit 1
}
