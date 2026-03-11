#!/usr/bin/env bash
# Integration test for decision log write→read loop
# Usage: bash tests/scripts/test_decision_loop.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DECISIONS_PY="$REPO_ROOT/system/scripts/decisions.py"

# Use a temp dir for isolation
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Override state dir via environment
export BRANA_DECISIONS_DIR="$TEST_DIR/decisions"
export BRANA_SESSION_ID="test-$$"

PASS=0
FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected='$expected', got='$actual')"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" expected="$2" actual="$3"
    if echo "$actual" | grep -q "$expected"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected to contain '$expected', got='$actual')"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Decision Log Integration Test ==="
echo ""

# Step 1: Log 3 entries
echo "Step 1: Log entries"
uv run python3 "$DECISIONS_PY" log main finding "Critical auth vulnerability" --severity HIGH --refs t-100,t-101
uv run python3 "$DECISIONS_PY" log scout action "Created tracking issue" --severity LOW
uv run python3 "$DECISIONS_PY" log challenger concern "Architecture mismatch" --severity MEDIUM --refs doc-14

# Step 2: Read all — verify 3 entries
echo "Step 2: Read all entries"
ALL=$(uv run python3 "$DECISIONS_PY" read --json)
COUNT=$(echo "$ALL" | wc -l)
assert_eq "3 entries logged" "3" "$COUNT"

# Step 3: Read --severity HIGH — verify 1 entry
echo "Step 3: Filter by severity"
HIGH=$(uv run python3 "$DECISIONS_PY" read --severity HIGH --json)
HIGH_COUNT=$(echo "$HIGH" | wc -l)
assert_eq "1 HIGH entry" "1" "$HIGH_COUNT"
assert_contains "HIGH entry is the auth finding" "auth vulnerability" "$HIGH"

# Step 4: Read --last 1 — verify 1 entry
echo "Step 4: Read last 1"
LAST=$(uv run python3 "$DECISIONS_PY" read --last 1 --json)
LAST_COUNT=$(echo "$LAST" | wc -l)
assert_eq "1 entry returned" "1" "$LAST_COUNT"

# Step 5: Read --type finding — verify 1 entry
echo "Step 5: Filter by type"
FINDINGS=$(uv run python3 "$DECISIONS_PY" read --type finding --json)
FIND_COUNT=$(echo "$FINDINGS" | wc -l)
assert_eq "1 finding entry" "1" "$FIND_COUNT"

# Step 6: Read --agent scout — verify 1 entry
echo "Step 6: Filter by agent"
SCOUT=$(uv run python3 "$DECISIONS_PY" read --agent scout --json)
SCOUT_COUNT=$(echo "$SCOUT" | wc -l)
assert_eq "1 scout entry" "1" "$SCOUT_COUNT"

# Step 7: Archive with --days 0 — verify file moved
echo "Step 7: Archive"
ARCHIVE_OUT=$(uv run python3 "$DECISIONS_PY" archive --days 0)
assert_contains "archive reported" "Archived" "$ARCHIVE_OUT"

# Verify file moved to archive/
ARCHIVE_COUNT=$(find "$TEST_DIR/decisions/archive" -maxdepth 1 -name '*.jsonl' 2>/dev/null | wc -l)
assert_eq "1 file in archive" "1" "$ARCHIVE_COUNT"

# Verify no files remain in active dir
ACTIVE_COUNT=$(find "$TEST_DIR/decisions" -maxdepth 1 -name '*.jsonl' 2>/dev/null | wc -l)
assert_eq "0 files in active dir" "0" "$ACTIVE_COUNT"

# Step 8: Formatted output (non-JSON)
echo "Step 8: Formatted output"
# Log a fresh entry after archive
export BRANA_SESSION_ID="test-format-$$"
uv run python3 "$DECISIONS_PY" log main decision "Test formatted output" --severity MEDIUM
FORMATTED=$(uv run python3 "$DECISIONS_PY" read)
assert_contains "formatted output has agent/type" "main/decision" "$FORMATTED"
assert_contains "formatted output has severity" "[MEDIUM]" "$FORMATTED"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
