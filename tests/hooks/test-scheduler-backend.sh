#!/usr/bin/env bash
# system/hooks/lib/scheduler-backend.sh — capability probe shared by every scheduler-adjacent
# surface (t-3375). A host has a scheduler backend iff systemctl is on PATH.
# Run: bash tests/hooks/test-scheduler-backend.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$ROOT/system/hooks/lib/scheduler-backend.sh"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
echo "=== test-scheduler-backend.sh ==="
[ -f "$LIB" ] || { echo "  FAIL: $LIB missing"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/with" "$T/without"
printf '#!/bin/sh\nexit 0\n' >"$T/with/systemctl"; chmod +x "$T/with/systemctl"
run() { PATH="$1" "$(command -v bash)" -c "source '$LIB'; $2" 2>&1; }

assert "systemctl on PATH -> available (rc 0)" 0 "$(run "$T/with" 'sched_backend_available; echo $?')"
assert "no systemctl on PATH -> unavailable (rc 1)" 1 "$(run "$T/without" 'sched_backend_available; echo $?')"
assert "a non-executable systemctl does not count" 1 \
    "$(mkdir -p "$T/noexec"; printf 'x\n' >"$T/noexec/systemctl"; chmod -x "$T/noexec/systemctl"; run "$T/noexec" 'sched_backend_available; echo $?')"
note="$(run "$T/without" 'sched_backend_note')"
case "$note" in *"no scheduler backend"*) assert "note says there is no scheduler backend" ok ok;; *) assert "note says there is no scheduler backend" ok "$note";; esac
case "$note" in *"always-on"*) assert "note points at the always-on host" ok ok;; *) assert "note points at the always-on host" ok "$note";; esac
case "$note" in *"ADR-071"*) assert "note cites ADR-071" ok ok;; *) assert "note cites ADR-071" ok "$note";; esac
assert "note is a single line" 1 "$(printf '%s\n' "$note" | wc -l | tr -d ' ')"
# BRANA_SCHEDULER_BACKEND=none|systemd|auto — explicit override (opt a systemd host out, or force for tests)
assert "override none beats a present systemctl" 1 "$(BRANA_SCHEDULER_BACKEND=none run "$T/with" 'sched_backend_available; echo $?')"
assert "override systemd beats an absent systemctl" 0 "$(BRANA_SCHEDULER_BACKEND=systemd run "$T/without" 'sched_backend_available; echo $?')"
assert "override auto probes (present)" 0 "$(BRANA_SCHEDULER_BACKEND=auto run "$T/with" 'sched_backend_available; echo $?')"
assert "override auto probes (absent)" 1 "$(BRANA_SCHEDULER_BACKEND=auto run "$T/without" 'sched_backend_available; echo $?')"
assert "unknown override value falls back to probing" 1 "$(BRANA_SCHEDULER_BACKEND=bogus run "$T/without" 'sched_backend_available; echo $?')"
assert "note names the override when the host was opted out" "yes" \
    "$(BRANA_SCHEDULER_BACKEND=none run "$T/with" 'sched_backend_note' | grep -q 'BRANA_SCHEDULER_BACKEND' && echo yes || echo no)"
assert "sourcing does not fork or print" "" "$(run "$T/without" ':')"
echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
