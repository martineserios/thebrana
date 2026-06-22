#!/usr/bin/env bash
# Tests for presence-refresh.sh (t-2205, ADR-061 §4 invariant 1).
# Run from anywhere: bash system/hooks/tests/test-presence-refresh.sh
#
# Note: this harness runs without a controlling terminal (/dev/tty not openable), which is
# exactly the headless threat model. So it proves the SECURITY property — a headless run does
# NOT forge a presence token even with a valid session_id. The interactive write path
# (tty present → token written) is exercised in real sessions.

HOOK_SRC="$(cd "$(dirname "$0")/.." && pwd)/presence-refresh.sh"
PASS=0; FAIL=0; TOTAL=0

run_hook() {            # run_hook <session_id-json> ; uses sandboxed HOME
    printf '%s' "$1" | HOME="$SBX" bash "$HOOK_SRC" 2>/dev/null
}

SBX=$(mktemp -d)
mkdir -p "$SBX/.claude/run-state"

check() { TOTAL=$((TOTAL+1)); if eval "$2"; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; FAIL=$((FAIL+1)); fi; }

# T1 — output contract: always continue:true
echo "T1: emits continue:true"
OUT=$(run_hook '{"prompt":"hi","session_id":"sid-1"}')
check "output is continue:true" '[ -n "$(echo "$OUT" | grep -F "\"continue\": true")" ]'

# T2 — SECURITY: headless (no /dev/tty) must NOT forge a presence token
echo "T2: headless run does not write presence token (no /dev/tty)"
rm -f "$SBX/.claude/run-state/presence-sid-1"
run_hook '{"prompt":"hi","session_id":"sid-1"}' >/dev/null
# If this harness somehow HAS a tty, skip the assertion rather than false-fail.
if { : > /dev/tty; } 2>/dev/null; then
    echo "  SKIP: /dev/tty present in harness — interactive path; security assertion N/A"
else
    check "no presence-sid-1 written when no tty" '[ ! -f "$SBX/.claude/run-state/presence-sid-1" ]'
fi

# T3 — empty session_id: no token, still continues
echo "T3: empty session_id writes nothing, continues"
OUT=$(run_hook '{"prompt":"hi"}')
check "continue:true on empty session_id" '[ -n "$(echo "$OUT" | grep -F "\"continue\": true")" ]'
check "no stray presence- file for empty sid" '[ -z "$(ls "$SBX/.claude/run-state/" | grep "^presence-$")" ]'

# T4 — malformed stdin does not crash (hooks must never block the session)
echo "T4: malformed stdin still emits continue:true"
OUT=$(printf 'not json' | HOME="$SBX" bash "$HOOK_SRC" 2>/dev/null)
check "continue:true on malformed input" '[ -n "$(echo "$OUT" | grep -F "\"continue\": true")" ]'

rm -rf "$SBX"
echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
