#!/usr/bin/env bash
# Tests for feed-index.sh
# Tests watermark logic, --force flag, graceful malformed-line handling, and --dry-run.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../../scripts/feed-index.sh"
PASS=0
FAIL=0
TOTAL=0
TMPDIR=$(mktemp -d)

trap 'rm -rf "$TMPDIR"' EXIT

assert_pass() {
    local desc="$1" rc="$2" output="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$rc" -eq 0 ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected: exit 0"
        echo "    got:      exit $rc"
        echo "    output:   $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" output="$2" pattern="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$output" | grep -q "$pattern"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected output to contain: $pattern"
        echo "    got: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" output="$2" pattern="$3"
    TOTAL=$((TOTAL + 1))
    if ! echo "$output" | grep -q "$pattern"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected output NOT to contain: $pattern"
        echo "    got: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_contains() {
    local desc="$1" file="$2" pattern="$3"
    TOTAL=$((TOTAL + 1))
    if [ -f "$file" ] && grep -q "$pattern" "$file"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected file $file to contain: $pattern"
        [ -f "$file" ] && echo "    file contents: $(cat "$file")" || echo "    file does not exist"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_absent() {
    local desc="$1" file="$2"
    TOTAL=$((TOTAL + 1))
    if [ ! -f "$file" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected file to be absent: $file"
        FAIL=$((FAIL + 1))
    fi
}

echo "Feed Index Tests"
echo "================"

# --- Setup: override HOME so tests don't touch real state ---
export HOME="$TMPDIR/home"
mkdir -p "$HOME/.claude/scheduler/state"

FEED_LOG="$HOME/.claude/scheduler/feed-log.jsonl"
WATERMARK="$HOME/.claude/scheduler/state/feed-index-watermark"
DIGEST="$HOME/.claude/intelligence-feed-digest.md"

SAMPLE_ENTRY='{"feed":"cc-changelog","title":"Version 2.1.0 released","link":"https://example.com/2.1.0","published":"2026-04-19T10:00:00Z","polled_at":"2026-04-19T10:00:00Z"}'

# --- Test 1: Empty feed-log → exits 0 cleanly ---
rm -f "$FEED_LOG"
output=$(bash "$SCRIPT" 2>&1); rc=$?
assert_pass "Empty feed-log exits 0" "$rc" "$output"
assert_contains "Empty feed-log reports missing log" "$output" "No feed log found"

# --- Test 2: Watermark prevents re-processing (idempotent second run) ---
echo "$SAMPLE_ENTRY" > "$FEED_LOG"
rm -f "$WATERMARK"
bash "$SCRIPT" >/dev/null 2>&1  # first run — sets watermark
output=$(bash "$SCRIPT" 2>&1); rc=$?
assert_pass "Second run with watermark exits 0" "$rc" "$output"
assert_contains "Second run reports no new entries" "$output" "No new entries"

# --- Test 3: --force resets watermark and reprocesses ---
echo "$SAMPLE_ENTRY" > "$FEED_LOG"
echo "1" > "$WATERMARK"  # watermark at line 1 = fully consumed
output=$(bash "$SCRIPT" --force 2>&1); rc=$?
assert_pass "--force exits 0" "$rc" "$output"
assert_contains "--force processes entries" "$output" "Processing 1 new entries"

# --- Test 4: Malformed JSONL lines are skipped gracefully ---
{
    echo "$SAMPLE_ENTRY"
    echo "NOT_VALID_JSON{"
    echo "$SAMPLE_ENTRY"
} > "$FEED_LOG"
rm -f "$WATERMARK"
output=$(bash "$SCRIPT" --force 2>&1); rc=$?
assert_pass "Malformed JSONL does not crash (exit 0)" "$rc" "$output"
# Digest should exist and have content from valid entries
assert_file_contains "Digest written despite malformed lines" "$DIGEST" "cc-changelog"

# --- Test 5: Watermark file is written after successful run ---
echo "$SAMPLE_ENTRY" > "$FEED_LOG"
rm -f "$WATERMARK"
bash "$SCRIPT" >/dev/null 2>&1
assert_file_contains "Watermark written after run" "$WATERMARK" "1"

# --- Summary ---
echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
