#!/usr/bin/env bash
# Tests: post-tasks-validate.sh's jq fallback branch (USE_RUST=false — no
# brana binary reachable) must take the same flock lock the CLI does
# (`<file>.json.lock`) before its read-modify-write, instead of racing an
# external writer unlocked. (t-3284, ADR-091 decision 4 — "take the lock the
# same way the CLI does... this closes the one unlocked writer").
#
# Added after the challenger gate on this task's first commit flagged that
# the canonical-resolution test alone doesn't cover this half of decision 4
# (severity 3, non-blocking but real coverage gap).
#
# Deterministic (no timing-race flakiness): an external holder acquires an
# exclusive flock on <file>.json.lock, sleeps briefly, then writes a
# "released-at" timestamp file the instant it releases. We invoke the hook
# concurrently and record when IT finishes. If the hook finishes BEFORE the
# external release timestamp, it never waited for the lock -- proving the
# unlocked-fallback defect. A fixed hook must finish AT OR AFTER release.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
HOOK_SRC="$REPO_ROOT/system/hooks/post-tasks-validate.sh"
LIB_SRC="$REPO_ROOT/system/hooks/lib/resolve-brana.sh"

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

if ! command -v flock >/dev/null 2>&1; then
    echo "SKIP: flock(1) not available on this system"
    exit 0
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Isolated fixture: copy just the hook + its lib, with no brana binary
# reachable anywhere (no target/release/brana alongside it, PATH stripped
# of any dir that has one) -- forces USE_RUST=false, exercising the fallback.
FIXTURE="$TMPDIR/fixture"
mkdir -p "$FIXTURE/hooks/lib" "$FIXTURE/.claude"
cp "$HOOK_SRC" "$FIXTURE/hooks/post-tasks-validate.sh"
cp "$LIB_SRC" "$FIXTURE/hooks/lib/resolve-brana.sh"
chmod +x "$FIXTURE/hooks/post-tasks-validate.sh"

TASKS_FILE="$FIXTURE/.claude/tasks.json"
# A rollup-eligible fixture so the fallback branch actually enters its
# cp/jq/mv read-modify-write sequence rather than short-circuiting.
cat > "$TASKS_FILE" <<'JSON'
{"version":"1","project":"fixture","tasks":[
  {"id":"ph-1","subject":"Phase","status":"pending","type":"phase"},
  {"id":"t-1","subject":"Child","status":"completed","type":"task","parent":"ph-1"}
]}
JSON

LOCK_FILE="${TASKS_FILE}.lock"
RELEASED_AT="$TMPDIR/released-at"
HOOK_DONE_AT="$TMPDIR/hook-done-at"

echo "post-tasks-validate.sh fallback-path lock tests"
echo "=================================================="
echo ""

echo "--- external holder takes the lock, hook must wait for it ---"
# External holder: exclusive flock for ~1.2s, then stamp the release time.
(
    exec 9>"$LOCK_FILE"
    flock -x 9
    sleep 1.2
    date +%s.%N > "$RELEASED_AT"
) &
HOLDER_PID=$!

# Give the holder a moment to actually acquire the lock before racing the hook.
sleep 0.2

(
    # Force fallback: no PLUGIN_DATA/PLUGIN_ROOT hints, PATH stripped down so
    # `command -v brana` fails, and the fixture has no target/release/brana.
    unset CLAUDE_PLUGIN_DATA CLAUDE_PLUGIN_ROOT
    export PATH="/usr/bin:/bin"
    INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$TASKS_FILE")
    echo "$INPUT" | "$FIXTURE/hooks/post-tasks-validate.sh" >/dev/null 2>&1
    date +%s.%N > "$HOOK_DONE_AT"
)

wait "$HOLDER_PID" 2>/dev/null || true

if [ -f "$RELEASED_AT" ] && [ -f "$HOOK_DONE_AT" ]; then
    RELEASED=$(cat "$RELEASED_AT")
    HOOK_DONE=$(cat "$HOOK_DONE_AT")
    # hook_done >= released (within a small epsilon for clock granularity)
    LATE_ENOUGH=$(awk -v a="$HOOK_DONE" -v b="$RELEASED" 'BEGIN{print (a >= b - 0.05) ? 1 : 0}')
    check "hook did not finish before the external lock was released" \
        "$([ "$LATE_ENOUGH" = "1" ] && echo 0 || echo 1)" \
        "hook finished at $HOOK_DONE, lock released at $RELEASED — hook returned before the lock it should have waited on was free, so its fallback read-modify-write was unlocked"
else
    check "both timing markers were written" 1 "released_at=$([ -f "$RELEASED_AT" ] && echo present || echo missing) hook_done_at=$([ -f "$HOOK_DONE_AT" ] && echo present || echo missing)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
