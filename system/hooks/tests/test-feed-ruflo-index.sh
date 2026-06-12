#!/usr/bin/env bash
# Tests for feed-ruflo-index.sh
# Tests watermark logic, --dry-run (no watermark update), and jq key schema.
# Does NOT call mcp-index.mjs — the --dry-run flag passes it through but we
# stub the node call to avoid a live ruflo dependency.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../../scripts/feed-ruflo-index.sh"
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

assert_file_absent() {
    local desc="$1" file="$2"
    TOTAL=$((TOTAL + 1))
    if [ ! -f "$file" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected file absent: $file"
        echo "    contents: $(cat "$file")"
        FAIL=$((FAIL + 1))
    fi
}

assert_json_key() {
    local desc="$1" jsonl_file="$2" expected_key="$3"
    TOTAL=$((TOTAL + 1))
    if jq -e --arg k "$expected_key" 'select(.key == $k)' "$jsonl_file" >/dev/null 2>&1; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected key: $expected_key"
        echo "    actual keys: $(jq -r '.key' "$jsonl_file" 2>/dev/null)"
        FAIL=$((FAIL + 1))
    fi
}

echo "Feed Ruflo Index Tests"
echo "======================"

# --- Setup: override HOME and stub node + mcp-index.mjs ---
export HOME="$TMPDIR/home"
mkdir -p "$HOME/.claude/scheduler/state"

FEED_LOG="$HOME/.claude/scheduler/feed-log.jsonl"
WATERMARK="$HOME/.claude/scheduler/state/feed-ruflo-watermark"

# Stub mcp-index.mjs: write the sections file to a known path so we can inspect it
STUB_SECTIONS="$TMPDIR/last-sections.jsonl"
STUB_MCP="$TMPDIR/mcp-index.mjs"
cat > "$STUB_MCP" <<'STUB'
#!/usr/bin/env node
import { existsSync, copyFileSync } from 'fs';
const args = process.argv.slice(2);
const sectionsFile = args.filter(a => !a.startsWith('--')).pop();
if (sectionsFile && existsSync(sectionsFile)) {
    copyFileSync(sectionsFile, process.env.STUB_SECTIONS_OUT);
}
STUB
chmod +x "$STUB_MCP"
export STUB_SECTIONS_OUT="$STUB_SECTIONS"

# Patch the script to use our stub mcp-index.mjs by symlinking
SCRIPTS_DIR="$TMPDIR/scripts"
mkdir -p "$SCRIPTS_DIR"
cp "$SCRIPT_DIR/../../scripts/feed-ruflo-index.sh" "$SCRIPTS_DIR/feed-ruflo-index.sh"
cp "$STUB_MCP" "$SCRIPTS_DIR/mcp-index.mjs"
SCRIPT="$SCRIPTS_DIR/feed-ruflo-index.sh"

SAMPLE_ENTRY='{"feed":"cc-changelog","title":"Version 2.1.0 released","link":"https://example.com/2.1.0","published":"2026-04-19T10:00:00Z","polled_at":"2026-04-19T10:00:00Z"}'

# --- Test 1: Empty feed-log exits 0 cleanly ---
rm -f "$FEED_LOG"
output=$(bash "$SCRIPT" 2>&1); rc=$?
assert_pass "Empty feed-log exits 0" "$rc" "$output"
assert_contains "Empty feed-log reports missing log" "$output" "No feed log"

# --- Test 2: Watermark prevents re-processing ---
echo "$SAMPLE_ENTRY" > "$FEED_LOG"
rm -f "$WATERMARK"
bash "$SCRIPT" >/dev/null 2>&1  # first run
output=$(bash "$SCRIPT" 2>&1); rc=$?
assert_pass "Second run exits 0" "$rc" "$output"
assert_contains "Second run reports no new entries" "$output" "No new entries"

# --- Test 3: --dry-run does NOT update watermark ---
rm -f "$WATERMARK"
echo "$SAMPLE_ENTRY" > "$FEED_LOG"
bash "$SCRIPT" --dry-run >/dev/null 2>&1; rc=$?
assert_file_absent "--dry-run does not write watermark" "$WATERMARK"

# --- Test 4: jq transform produces correct key schema ---
# key must be: knowledge:feed:{feed}:{slug}
# For title "Version 2.1.0 released" and feed "cc-changelog":
# slug = "version-2-1-0-released"
echo "$SAMPLE_ENTRY" > "$FEED_LOG"
rm -f "$WATERMARK" "$STUB_SECTIONS"
bash "$SCRIPT" >/dev/null 2>&1
assert_json_key "jq produces key: knowledge:feed:cc-changelog:version-2-1-0-released" \
    "$STUB_SECTIONS" "knowledge:feed:cc-changelog:version-2-1-0-released"

# --- Test 5: Malformed line in the window does not crash; watermark advances (t-2008) ---
# A partial write (e.g. from a non-Rust appender) must not strand the watermark
# in an infinite retry loop.
{
    echo "$SAMPLE_ENTRY"
    echo 'NOT_VALID_JSON{truncated'
    echo "$SAMPLE_ENTRY"
} > "$FEED_LOG"
rm -f "$WATERMARK" "$STUB_SECTIONS"
output=$(bash "$SCRIPT" 2>&1); rc=$?
assert_pass "Malformed line in window exits 0" "$rc" "$output"
assert_contains "Valid entries still converted" "$output" "2 sections ready"
assert_contains "Watermark advances past malformed line" "$(cat "$WATERMARK" 2>/dev/null || echo missing)" "^3$"

# --- Test 6: All-malformed window exits 0 without calling indexer ---
echo 'garbage-not-json' > "$FEED_LOG"
rm -f "$WATERMARK" "$STUB_SECTIONS"
output=$(bash "$SCRIPT" 2>&1); rc=$?
assert_pass "All-malformed window exits 0" "$rc" "$output"

# --- Summary ---
echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
