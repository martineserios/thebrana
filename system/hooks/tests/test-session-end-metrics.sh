#!/usr/bin/env bash
# Tests for session-end-metrics.sh — PROJECT_FILTER bucketing (t-1092)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METRICS="$SCRIPT_DIR/../session-end-metrics.sh"
PASS=0; FAIL=0; TOTAL=0
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

assert_eq() {
    local desc="$1" got="$2" expected="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$got" = "$expected" ]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    got:      $got"
        FAIL=$((FAIL + 1))
    fi
}

run_metrics() {
    local session_file="$1" project_filter="${2:-}"
    local env_file
    env_file=$(mktemp "$TMPDIR_TEST/metrics-XXXXXX.env")
    SESSION_FILE="$session_file" \
    METRICS_ENV_FILE="$env_file" \
    PROJECT_FILTER="$project_filter" \
        bash "$METRICS" 2>/dev/null
    echo "$env_file"
}

load_env() {
    local env_file="$1" var="$2"
    grep "^${var}=" "$env_file" 2>/dev/null | cut -d= -f2- | tr -d "'"
}

echo "Session End Metrics Tests — PROJECT_FILTER bucketing"
echo "====================================================="

# ── Build a mixed JSONL with events from two repos ───────────
MIXED_JSONL="$TMPDIR_TEST/mixed-session.jsonl"
cat > "$MIXED_JSONL" <<'JSONL'
{"ts":1,"tool":"Edit","outcome":"success","detail":"/home/user/alpha/foo.py","repo":"alpha"}
{"ts":2,"tool":"Edit","outcome":"correction","detail":"/home/user/alpha/foo.py","repo":"alpha"}
{"ts":3,"tool":"Edit","outcome":"success","detail":"/home/user/beta/bar.py","repo":"beta"}
{"ts":4,"tool":"Edit","outcome":"correction","detail":"/home/user/beta/bar.py","repo":"beta"}
{"ts":5,"tool":"Edit","outcome":"correction","detail":"/home/user/beta/baz.py","repo":"beta"}
JSONL

echo ""
echo "--- No filter: all events counted ---"

ENV_FILE=$(run_metrics "$MIXED_JSONL")
EDITS=$(load_env "$ENV_FILE" "EDITS")
CORRECTIONS=$(load_env "$ENV_FILE" "CORRECTIONS")

assert_eq "No filter: EDITS=5" "$EDITS" "5"
assert_eq "No filter: CORRECTIONS=3" "$CORRECTIONS" "3"

echo ""
echo "--- Filter to alpha: only 2 events ---"

ENV_FILE=$(run_metrics "$MIXED_JSONL" "alpha")
EDITS=$(load_env "$ENV_FILE" "EDITS")
CORRECTIONS=$(load_env "$ENV_FILE" "CORRECTIONS")

assert_eq "Filter alpha: EDITS=2" "$EDITS" "2"
assert_eq "Filter alpha: CORRECTIONS=1" "$CORRECTIONS" "1"

echo ""
echo "--- Filter to beta: only 3 events ---"

ENV_FILE=$(run_metrics "$MIXED_JSONL" "beta")
EDITS=$(load_env "$ENV_FILE" "EDITS")
CORRECTIONS=$(load_env "$ENV_FILE" "CORRECTIONS")

assert_eq "Filter beta: EDITS=3" "$EDITS" "3"
assert_eq "Filter beta: CORRECTIONS=2" "$CORRECTIONS" "2"

echo ""
echo "--- Filter to unknown repo: zero events ---"

ENV_FILE=$(run_metrics "$MIXED_JSONL" "nonexistent")
EDITS=$(load_env "$ENV_FILE" "EDITS")
CORRECTIONS=$(load_env "$ENV_FILE" "CORRECTIONS")

assert_eq "Filter nonexistent: EDITS=0" "$EDITS" "0"
assert_eq "Filter nonexistent: CORRECTIONS=0" "$CORRECTIONS" "0"

echo ""
echo "--- Legacy events (no repo field): included when filter set ---"

LEGACY_JSONL="$TMPDIR_TEST/legacy-session.jsonl"
cat > "$LEGACY_JSONL" <<'JSONL'
{"ts":1,"tool":"Edit","outcome":"success","detail":"/home/user/alpha/foo.py"}
{"ts":2,"tool":"Edit","outcome":"correction","detail":"/home/user/alpha/foo.py"}
{"ts":3,"tool":"Edit","outcome":"success","detail":"/home/user/beta/bar.py","repo":"beta"}
JSONL

# Legacy events (no repo field) should be included when filtering — backward compat
ENV_FILE=$(run_metrics "$LEGACY_JSONL" "alpha")
EDITS=$(load_env "$ENV_FILE" "EDITS")

assert_eq "Legacy events (no repo) included under any filter: EDITS=2" "$EDITS" "2"

echo ""
echo "--- Empty file: zeros regardless of filter ---"

EMPTY_JSONL="$TMPDIR_TEST/empty.jsonl"
touch "$EMPTY_JSONL"

ENV_FILE=$(run_metrics "$EMPTY_JSONL" "alpha")
EDITS=$(load_env "$ENV_FILE" "EDITS")
assert_eq "Empty file: EDITS=0" "${EDITS:-0}" "0"

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
