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

# --- Setup for chunk tests (t-2076): counting/appending stub that can fail on demand ---
# The default stub overwrites STUB_SECTIONS_OUT per call; chunked runs invoke the
# indexer once per chunk, so this stub APPENDS and tracks an invocation counter.
CHUNK_STUB="$TMPDIR/mcp-index-chunk.mjs"
cat > "$CHUNK_STUB" <<'STUB'
#!/usr/bin/env node
import { existsSync, readFileSync, writeFileSync, appendFileSync } from 'fs';
const args = process.argv.slice(2);
const sectionsFile = args.filter(a => !a.startsWith('--')).pop();
const cf = process.env.STUB_COUNT_FILE;
let n = 1;
if (cf && existsSync(cf)) n = parseInt(readFileSync(cf, 'utf8') || '0', 10) + 1;
if (cf) writeFileSync(cf, String(n));
if (process.env.STUB_FAIL_ON && n === parseInt(process.env.STUB_FAIL_ON, 10)) process.exit(1);
if (sectionsFile && existsSync(sectionsFile)) {
    appendFileSync(process.env.STUB_SECTIONS_OUT, readFileSync(sectionsFile));
}
STUB
cp "$CHUNK_STUB" "$SCRIPTS_DIR/mcp-index.mjs"
export STUB_COUNT_FILE="$TMPDIR/stub-count"

five_entries() {
    for i in 1 2 3 4 5; do
        printf '{"feed":"cc-changelog","title":"Entry %s","link":"https://example.com/%s","published":"2026-06-12T10:00:00Z","polled_at":"2026-06-12T10:00:00Z"}\n' "$i" "$i"
    done
}

# --- Test 7: chunked run indexes everything and advances watermark to total ---
five_entries > "$FEED_LOG"
rm -f "$WATERMARK" "$STUB_SECTIONS" "$STUB_COUNT_FILE"
output=$(FEED_RUFLO_CHUNK=2 bash "$SCRIPT" 2>&1); rc=$?
assert_pass "Chunked run exits 0" "$rc" "$output"
assert_contains "All sections indexed across chunks" "$(wc -l < "$STUB_SECTIONS" 2>/dev/null | tr -d ' ')" "^5$"
assert_contains "Indexer invoked once per chunk" "$(cat "$STUB_COUNT_FILE" 2>/dev/null)" "^3$"
assert_contains "Watermark reaches total after chunked run" "$(cat "$WATERMARK" 2>/dev/null || echo missing)" "^5$"

# --- Test 8: indexer failure mid-run keeps completed chunks' watermark (t-2076) ---
# A timeout/crash on chunk 2 must not strand the watermark at the run's start —
# that is the infinite zero-progress loop this fix removes.
five_entries > "$FEED_LOG"
rm -f "$WATERMARK" "$STUB_SECTIONS" "$STUB_COUNT_FILE"
output=$(FEED_RUFLO_CHUNK=2 STUB_FAIL_ON=2 bash "$SCRIPT" 2>&1); rc=$?
assert_contains "Failed chunk exits nonzero" "$rc" "^[^0]"
assert_contains "Watermark holds completed chunk 1 (line 2)" "$(cat "$WATERMARK" 2>/dev/null || echo missing)" "^2$"
assert_contains "Only chunk 1 sections indexed" "$(wc -l < "$STUB_SECTIONS" 2>/dev/null | tr -d ' ')" "^2$"

# --- Summary ---
echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
