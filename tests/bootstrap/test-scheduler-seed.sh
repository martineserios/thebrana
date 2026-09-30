#!/usr/bin/env bash
# bootstrap.sh scheduler seeding on hosts with / without a scheduler backend (t-3375).
# A backend-less host (the Mac) must not get a Linux-path scheduler.json nor be told to run
# `brana-scheduler deploy`; a systemd host keeps the old behaviour. --check is a non-mutating dry run.
# Run: bash tests/bootstrap/test-scheduler-seed.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }

H="$(mktemp -d)"; trap 'rm -rf "$H"' EXIT
echo "=== test-scheduler-seed.sh ==="
NONE="$(cd "$ROOT" && HOME="$H" BRANA_SCHEDULER_BACKEND=none ./bootstrap.sh --check 2>&1)"
SYS="$(cd "$ROOT" && HOME="$H" BRANA_SCHEDULER_BACKEND=systemd ./bootstrap.sh --check 2>&1)"

assert "systemd host: would seed scheduler.json (unchanged behaviour)" yes "$(has 'scheduler/scheduler.json (would create from template)' "$SYS")"
assert "no backend: does NOT seed scheduler.json" no "$(has 'scheduler/scheduler.json (would create' "$NONE")"
assert "no backend: prints the shared note" yes "$(has 'no scheduler backend on this host' "$NONE")"
assert "no backend: still syncs the scheduler scripts (tree stays identical)" yes "$(has 'scheduler/brana-scheduler' "$NONE")"
assert "systemd host: no note" no "$(has 'no scheduler backend on this host' "$SYS")"
assert "no backend: never says to run brana-scheduler deploy" no "$(has 'brana-scheduler deploy' "$NONE")"
echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
