#!/usr/bin/env bash
# t-3351: tests/scripts/test-sync-state.sh must be hermetic.
#
# It used to drive the real sync-state.sh against the REAL repo and REAL $HOME: it wrote a
# fixture ({"theme":"minimal","_test_marker":true}) into the real system/state/tasks-config.json
# and ~/.claude/tasks-config.json, ran `push` against the real portfolio (writing into real client
# repos' .claude/memory/) and `import` against the real ruflo store. Its restore step was skipped on
# any interrupt, and sync-state.sh --auto-commit then committed the poisoned file.
#
# This guard never touches anything real. It builds a FIXTURE "real" repo + HOME + client repo in a
# temp dir, launches the suite from that fixture repo (the suite derives its REPO_ROOT from its own
# location), and SIGKILLs it the instant the fixture marker shows up in the fixture's config — the
# worst-case interrupt. A hermetic suite works in its own sandbox, so the marker never appears in
# the fixture and nothing in the fixture changes.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUITE_SRC="$ROOT/tests/scripts/test-sync-state.sh"
SYNC_SRC="$ROOT/system/scripts/sync-state.sh"
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT INT TERM

R="$T/realrepo"      # stands in for the real thebrana checkout
H="$T/realhome"      # stands in for the real $HOME
C="$T/client"        # stands in for a real client repo listed in the real portfolio
mkdir -p "$R/tests/scripts" "$R/system/scripts" "$R/system/state" "$H/.claude/memory" "$H/.claude/projects/-fixture-client/memory" "$C/.claude/memory"
cp "$SUITE_SRC" "$R/tests/scripts/test-sync-state.sh"
cp "$SYNC_SRC"  "$R/system/scripts/sync-state.sh"

REAL_CONFIG='{"theme":"emoji","github_sync":{"enabled":true}}'
echo "$REAL_CONFIG" > "$R/system/state/tasks-config.json"
echo "$REAL_CONFIG" > "$H/.claude/tasks-config.json"
echo "real-event-log" > "$R/system/state/event-log.md"
echo "real-event-log" > "$H/.claude/memory/event-log.md"
printf '{"clients":[{"name":"fx","projects":[{"slug":"client","path":"%s","type":"code"}]}]}\n' "$C" > "$H/.claude/tasks-portfolio.json"
echo "client" > "$H/.claude/projects/-fixture-client/memory/MEMORY.md"
echo "client-event-log" > "$H/.claude/projects/-fixture-client/memory/event-log.md"
echo "client-repo-file" > "$C/.claude/memory/event-log.md"

cd "$T"   # ruflo has a CWD-relative store path (ADR-026); never let it resolve inside a real tree
snapshot() { (cd "$T" && find realrepo/system/state realhome/.claude client -type f -print0 | sort -z | xargs -0 md5sum); }
BEFORE=$(snapshot)

echo "=== Scenario 1: an interrupted run leaves the fixture 'real' state untouched ==="
HOME="$H" bash "$R/tests/scripts/test-sync-state.sh" >"$T/suite.out" 2>&1 &
PID=$!
KILLED=0
while kill -0 "$PID" 2>/dev/null; do
    if grep -qs "_test_marker" "$R/system/state/tasks-config.json" "$H/.claude/tasks-config.json"; then
        kill -9 "$PID" 2>/dev/null; KILLED=1; break
    fi
    sleep 0.002
done
wait "$PID" 2>/dev/null
RC=$?
sleep 0.3   # let any orphaned child finish so the snapshot is stable
AFTER=$(snapshot)

[ "$KILLED" -eq 0 ] && ok "fixture marker never reached the fixture 'real' state (suite is sandboxed)" \
                     || bad "suite wrote its test marker into the fixture 'real' config — it is not hermetic"
[ "$BEFORE" = "$AFTER" ] && ok "no file in the fixture 'real' repo, HOME or client repo changed" \
                          || bad "fixture 'real' state changed: $(diff <(echo "$BEFORE") <(echo "$AFTER") | grep '^[<>]' | head -3 | tr '\n' ' ')"

echo "=== Scenario 2: an uninterrupted run passes and still leaves nothing behind ==="
HOME="$H" bash "$R/tests/scripts/test-sync-state.sh" >"$T/suite2.out" 2>&1
RC2=$?
AFTER2=$(snapshot)
[ "$RC2" -eq 0 ] && ok "suite passes when run from the fixture repo (exit 0)" || bad "suite failed (rc=$RC2): $(tail -3 "$T/suite2.out" | tr '\n' ' ')"
[ "$BEFORE" = "$AFTER2" ] && ok "fixture 'real' state unchanged after a full run" || bad "fixture 'real' state changed after a full run"
grep -qE "skipped \(no portfolio|no valid project path" "$T/suite2.out" \
    && bad "companion-sync tests were silently downgraded to a skip" \
    || ok "companion-sync tests still run (fixture portfolio is seeded)"

echo "=== Scenario 3: static guards ==="
grep -qE 'trap .*(INT|TERM)' "$SUITE_SRC" && ok "suite traps INT/TERM, not only EXIT" || bad "suite does not trap INT/TERM"
grep -q '/tmp/test-' "$SUITE_SRC" && bad "suite still writes fixed /tmp/test-* backup files" || ok "suite uses no fixed /tmp/test-* files"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
