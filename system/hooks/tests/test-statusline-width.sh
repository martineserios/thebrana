#!/usr/bin/env bash
# Tests for statusline width detection + progressive segment dropping.
# Validates that narrow terminals drop low-priority segments gracefully.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE="$SCRIPT_DIR/../../statusline.sh"
PASS=0
FAIL=0
TOTAL=0
TMPDIR=$(mktemp -d)

trap 'rm -rf "$TMPDIR"' EXIT

# ── Helpers ──────────────────────────────────────────────

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected: $expected"
        echo "    got:      $actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected to contain: $needle"
        echo "    got: $haystack"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected NOT to contain: $needle"
        echo "    got: $haystack"
        FAIL=$((FAIL + 1))
    fi
}

# Strip ANSI codes to get visible text
strip_ansi() {
    echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

visible_len() {
    local stripped
    stripped=$(strip_ansi "$1")
    # Use printf to avoid trailing newline issues, wc -m for char count
    printf '%s' "$stripped" | wc -m
}

# Build minimal JSON input for statusline
make_input() {
    cat <<'EOF'
{
  "model": {"display_name": "Opus 4"},
  "workspace": {"current_dir": "/tmp/wt-t-1020", "project_dir": "/tmp/wt-t-1020"},
  "context_window": {"used_percentage": 42},
  "cost": {"total_lines_added": 156, "total_lines_removed": 23}
}
EOF
}

# Build input with session score + scheduler for full segment coverage
make_full_input() {
    # Session score file
    echo -e "5\t1" > "$TMPDIR/session-score.tsv"
    # Scheduler status
    cat > "$TMPDIR/scheduler-status.json" <<'EOF'
[
  {"status": "SUCCESS"},
  {"status": "SUCCESS"},
  {"status": "FAILED"}
]
EOF
    # Tasks file with phase, current task, bugs, build step
    mkdir -p "$TMPDIR/.claude"
    cat > "$TMPDIR/.claude/tasks.json" <<'EOF'
{
  "version": "1.0",
  "project": "test",
  "last_modified": "2026-04-06T00:00:00Z",
  "tasks": [
    {"id": "t-001", "type": "phase", "status": "in_progress", "subject": "Phase 1: Foundation"},
    {"id": "t-002", "type": "task", "status": "completed", "subject": "Setup repo"},
    {"id": "t-003", "type": "task", "status": "completed", "subject": "Add CI"},
    {"id": "t-004", "type": "task", "status": "in_progress", "subject": "Width detection for statusline", "build_step": "TDD"},
    {"id": "t-005", "type": "task", "status": "pending", "subject": "Fix alignment", "stream": "bugs"},
    {"id": "t-006", "type": "task", "status": "pending", "subject": "Other task"}
  ]
}
EOF
    make_input
}

# Run statusline with controlled terminal width
# Usage: run_statusline <cols> [input_func]
run_statusline() {
    local cols="$1"
    local input_func="${2:-make_input}"

    # Override tput to return our desired columns
    # We export a function that replaces tput
    local env_vars="BRANA_STATUSLINE_COLS=$cols"

    if [ "$input_func" = "make_full_input" ]; then
        env_vars="$env_vars BRANA_SESSION_SCORE_FILE=$TMPDIR/session-score.tsv"
        # Point CWD to our temp dir with tasks
        local input
        input=$(make_full_input | jq --arg d "$TMPDIR" '.workspace.current_dir = $d | .workspace.project_dir = $d')
        echo "$input" | env $env_vars bash "$STATUSLINE" 2>/dev/null
    else
        $input_func | env $env_vars bash "$STATUSLINE" 2>/dev/null
    fi
}

# ── Tests ────────────────────────────────────────────────

echo "=== Statusline Width Detection Tests ==="

echo ""
echo "--- Wide terminal (200 cols) shows all segments ---"
OUTPUT=$(run_statusline 200)
STRIPPED=$(strip_ansi "$OUTPUT")
assert_contains "has model" "Opus 4" "$STRIPPED"
assert_contains "has project" "wt-t-1020" "$STRIPPED"
assert_contains "has CTX%" "42%" "$STRIPPED"
assert_contains "has lines added" "+156" "$STRIPPED"
assert_contains "has lines removed" "-23" "$STRIPPED"

echo ""
echo "--- Wide terminal output fits within width ---"
LEN=$(visible_len "$OUTPUT")
# Visible length should be well under 200
TOTAL=$((TOTAL + 1))
if (( LEN <= 200 )); then
    echo "  PASS: output length $LEN <= 200"
    PASS=$((PASS + 1))
else
    echo "  FAIL: output length $LEN > 200"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- Narrow terminal (80 cols) drops low-priority segments ---"
OUTPUT_80=$(run_statusline 80)
STRIPPED_80=$(strip_ansi "$OUTPUT_80")
# Must keep: model, project, CTX%
assert_contains "80col: has model" "Opus 4" "$STRIPPED_80"
assert_contains "80col: has CTX%" "42%" "$STRIPPED_80"
# Lines segment is low priority — should be dropped at 80 cols
# (model ~10 + project ~15 + branch ~30 + CTX ~10 + lines ~15 = ~80, tight)

LEN_80=$(visible_len "$OUTPUT_80")
TOTAL=$((TOTAL + 1))
if (( LEN_80 <= 80 )); then
    echo "  PASS: 80col output length $LEN_80 <= 80"
    PASS=$((PASS + 1))
else
    echo "  FAIL: 80col output length $LEN_80 > 80 (overflow)"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- Very narrow terminal (40 cols) shows only essentials ---"
OUTPUT_40=$(run_statusline 40)
STRIPPED_40=$(strip_ansi "$OUTPUT_40")
# Must keep: model, project, CTX% (the always-keep segments)
assert_contains "40col: has model" "Opus 4" "$STRIPPED_40"
assert_contains "40col: has CTX%" "%" "$STRIPPED_40"
# Should NOT have lines, phase, session score, scheduler
assert_not_contains "40col: no lines" "+156" "$STRIPPED_40"
assert_not_contains "40col: no session score" "S:" "$STRIPPED_40"

LEN_40=$(visible_len "$OUTPUT_40")
TOTAL=$((TOTAL + 1))
if (( LEN_40 <= 40 )); then
    echo "  PASS: 40col output length $LEN_40 <= 40"
    PASS=$((PASS + 1))
else
    echo "  FAIL: 40col output length $LEN_40 > 40 (overflow)"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- tput unavailable + BRANA_STATUSLINE_COLS unset = no-drop ---"
# Override tput to fail, simulating no terminal
OUTPUT_NOENV=$(make_input | env -u BRANA_STATUSLINE_COLS PATH="/usr/bin:/bin" TERM=dumb bash -c '
  tput() { return 1; }
  export -f tput
  bash "'"$STATUSLINE"'"
' 2>/dev/null)
STRIPPED_NOENV=$(strip_ansi "$OUTPUT_NOENV")
# Without any width constraint, all segments should be present
assert_contains "no-env: has model" "Opus 4" "$STRIPPED_NOENV"
assert_contains "no-env: has lines" "+156" "$STRIPPED_NOENV"

echo ""
echo "--- Full segments with task metrics on wide terminal ---"
OUTPUT_FULL=$(run_statusline 200 make_full_input)
STRIPPED_FULL=$(strip_ansi "$OUTPUT_FULL")
assert_contains "full: has phase" "Ph1" "$STRIPPED_FULL"
assert_contains "full: has current task" "Width detection" "$STRIPPED_FULL"
assert_contains "full: has build step" "[TDD]" "$STRIPPED_FULL"
assert_contains "full: has bugs" "1" "$STRIPPED_FULL"

echo ""
echo "--- Full segments on narrow terminal drops scheduler + lines + score first ---"
OUTPUT_FULL_80=$(run_statusline 80 make_full_input)
STRIPPED_FULL_80=$(strip_ansi "$OUTPUT_FULL_80")
# Always-keep segments must survive
assert_contains "full-80: has model" "Opus 4" "$STRIPPED_FULL_80"
assert_contains "full-80: has CTX%" "%" "$STRIPPED_FULL_80"

LEN_FULL_80=$(visible_len "$OUTPUT_FULL_80")
TOTAL=$((TOTAL + 1))
if (( LEN_FULL_80 <= 80 )); then
    echo "  PASS: full-80col output length $LEN_FULL_80 <= 80"
    PASS=$((PASS + 1))
else
    echo "  FAIL: full-80col output length $LEN_FULL_80 > 80 (overflow)"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
