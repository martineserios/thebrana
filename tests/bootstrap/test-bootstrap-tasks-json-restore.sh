#!/usr/bin/env bash
# Tests: bootstrap.sh restores .claude/tasks.json from the tracked snapshot
# (system/state/tasks-snapshot.json) on a fresh clone/worktree where the
# (now untracked, per ADR-091) live tasks.json is absent. (t-3284, ADR-091
# decision 5.)
#
# Expected contract (not yet implemented — this is the RED state until
# t-3287 lands): bootstrap.sh gains a function, expected name
# `restore_tasks_json_if_missing`, called near Step 4e (the existing
# tasks.json merge-driver wiring, bootstrap.sh:608) that:
#   - no-ops if .claude/tasks.json already exists (never overwrites live state)
#   - if missing AND system/state/tasks-snapshot.json exists: copies the
#     snapshot into .claude/tasks.json
#   - if missing AND no snapshot exists either: does nothing (leaves it to
#     find_tasks_file_from()'s existing auto-create-on-first-CLI-call
#     fallback — a genuinely first-ever setup, per ADR-091's Decision 5
#     "Bootstrap/fresh-clone" note)
#
# Static assertion mirrors tests/bootstrap/test-bootstrap-idempotent.sh's
# style: extract the function from bootstrap.sh rather than sourcing the
# whole script (which would run a real deploy to ~/.claude/).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"

PASS=0; FAIL=0; TOTAL=0
check() {
    local desc="$1" ok="$2" detail="${3:-}"
    TOTAL=$((TOTAL + 1))
    if [ "$ok" = "0" ]; then
        PASS=$((PASS + 1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL: $desc${detail:+ — $detail}"
    fi
}

echo "bootstrap.sh tasks.json restore-from-snapshot tests"
echo "======================================================"
echo ""

echo "--- static: bootstrap.sh calls the restore step ---"
grep -q "restore_tasks_json_if_missing" "$BOOTSTRAP"
check "bootstrap.sh references restore_tasks_json_if_missing" "$?" \
    "not found — this is the RED state until t-3287 wires it in near Step 4e"

echo ""
echo "--- behavioral: restore_tasks_json_if_missing ---"
FN=$(awk '/^restore_tasks_json_if_missing\(\) \{/{flag=1} flag{print} flag&&/^\}/{exit}' "$BOOTSTRAP")
if [ -z "$FN" ]; then
    check "restore_tasks_json_if_missing extractable" 1 "function not implemented yet"
else
    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT

    run_restore() {
        # Runs the extracted function in a subshell against a fixture repo
        # root, echoing whether .claude/tasks.json exists afterward.
        local root="$1"
        (
            REPO_ROOT="$root"
            eval "$FN"
            restore_tasks_json_if_missing
            [ -f "$root/.claude/tasks.json" ] && cat "$root/.claude/tasks.json" || echo "__ABSENT__"
        )
    }

    echo "  case 1: snapshot present, live file missing -> restores"
    R1="$TMPDIR/fresh-clone"
    mkdir -p "$R1/.claude" "$R1/system/state"
    echo '{"version":"1","project":"snap","tasks":[]}' > "$R1/system/state/tasks-snapshot.json"
    OUT1=$(run_restore "$R1")
    check "restores tasks.json from snapshot when missing" \
        "$([ "$OUT1" != "__ABSENT__" ] && echo 0 || echo 1)" "got: $OUT1"

    echo "  case 2: live file already present -> never overwritten"
    R2="$TMPDIR/existing"
    mkdir -p "$R2/.claude" "$R2/system/state"
    echo '{"version":"1","project":"live","tasks":[{"id":"t-1"}]}' > "$R2/.claude/tasks.json"
    echo '{"version":"1","project":"snap","tasks":[]}' > "$R2/system/state/tasks-snapshot.json"
    OUT2=$(run_restore "$R2")
    check "does not overwrite an existing live tasks.json" \
        "$(echo "$OUT2" | grep -q '"project":"live"' && echo 0 || echo 1)" "got: $OUT2"

    echo "  case 3: neither live file nor snapshot -> no-op (auto-create fallback owns this)"
    R3="$TMPDIR/first-ever"
    mkdir -p "$R3/.claude" "$R3/system/state"
    OUT3=$(run_restore "$R3")
    check "no-ops when no snapshot exists (leaves auto-create fallback in charge)" \
        "$([ "$OUT3" = "__ABSENT__" ] && echo 0 || echo 1)" "got: $OUT3"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
