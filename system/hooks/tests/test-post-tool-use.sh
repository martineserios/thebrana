#!/usr/bin/env bash
# Tests for post-tool-use.sh — repo field bucketing (t-1092)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../post-tool-use.sh"
PASS=0; FAIL=0; TOTAL=0
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

assert() {
    local desc="$1" result="$2" expected="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$result" = "$expected" ]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    got:      $result"
        FAIL=$((FAIL + 1))
    fi
}

setup_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main 2>/dev/null
    git -C "$dir" config user.email "test@test.com"
    git -C "$dir" config user.name "Test"
    echo "init" > "$dir/init.txt"
    git -C "$dir" add -A && git -C "$dir" commit -q -m "init" 2>/dev/null
}

run_hook() {
    local input="$1"
    echo "$input" | bash "$HOOK" 2>/dev/null
}

echo "Post Tool Use Tests — repo bucketing"
echo "====================================="

# ── Setup ─────────────────────────────────────────────────────
REPO_A="$TMPDIR_TEST/project-alpha"
REPO_B="$TMPDIR_TEST/project-beta"
setup_repo "$REPO_A"
setup_repo "$REPO_B"

SESSION_ID="test-ptu-$(date +%s)"
SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"
trap 'rm -rf "$TMPDIR_TEST" "$SESSION_FILE"' EXIT

echo ""
echo "--- Repo field in JSONL event ---"

# Event from repo-alpha should include repo field
run_hook "{\"session_id\":\"$SESSION_ID\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$REPO_A/foo.py\"},\"cwd\":\"$REPO_A\"}" >/dev/null
sleep 0.1  # allow background write

TOTAL=$((TOTAL + 1))
if [ -f "$SESSION_FILE" ]; then
    REPO_FIELD=$(tail -1 "$SESSION_FILE" | jq -r '.repo // empty' 2>/dev/null)
    if [ "$REPO_FIELD" = "project-alpha" ]; then
        echo "  PASS: Edit event includes repo field (project-alpha)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Edit event includes repo field"
        echo "    expected: project-alpha"
        echo "    got:      $REPO_FIELD"
        echo "    event:    $(tail -1 "$SESSION_FILE" 2>/dev/null)"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL: SESSION_FILE not created"
    FAIL=$((FAIL + 1))
fi

# Event from repo-beta should have different repo field
run_hook "{\"session_id\":\"$SESSION_ID\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$REPO_B/bar.py\"},\"cwd\":\"$REPO_B\"}" >/dev/null
sleep 0.1

TOTAL=$((TOTAL + 1))
if [ -f "$SESSION_FILE" ]; then
    REPO_FIELD=$(tail -1 "$SESSION_FILE" | jq -r '.repo // empty' 2>/dev/null)
    if [ "$REPO_FIELD" = "project-beta" ]; then
        echo "  PASS: Edit event from second repo has correct repo field (project-beta)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Edit event from second repo has correct repo field"
        echo "    expected: project-beta"
        echo "    got:      $REPO_FIELD"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL: SESSION_FILE not found after second event"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- Two repos produce separately filterable events ---"

EVENT_COUNT=$(wc -l < "$SESSION_FILE" 2>/dev/null | tr -d ' ') || EVENT_COUNT=0
ALPHA_COUNT=$(jq -r 'select(.repo == "project-alpha")' "$SESSION_FILE" 2>/dev/null | grep -c '"repo"' || echo 0)
BETA_COUNT=$(jq -r 'select(.repo == "project-beta")' "$SESSION_FILE" 2>/dev/null | grep -c '"repo"' || echo 0)

assert "Total events = 2" "$EVENT_COUNT" "2"
assert "Alpha events = 1" "$ALPHA_COUNT" "1"
assert "Beta events = 1" "$BETA_COUNT" "1"

echo ""
echo "--- Missing CWD falls back gracefully ---"

SESSION_ID2="test-ptu-nocwd-$(date +%s)"
SESSION_FILE2="/tmp/brana-session-${SESSION_ID2}.jsonl"
trap 'rm -rf "$TMPDIR_TEST" "$SESSION_FILE" "$SESSION_FILE2"' EXIT

run_hook "{\"session_id\":\"$SESSION_ID2\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/tmp/foo.py\"}}" >/dev/null
sleep 0.1

TOTAL=$((TOTAL + 1))
if [ -f "$SESSION_FILE2" ]; then
    # repo field should be empty string or missing, but event must be valid JSON
    if tail -1 "$SESSION_FILE2" | jq -e '.' >/dev/null 2>&1; then
        echo "  PASS: Missing CWD still writes valid JSON event"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Missing CWD produced invalid JSON"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL: SESSION_FILE not created for no-CWD event"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
