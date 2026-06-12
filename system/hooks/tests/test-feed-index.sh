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

# --- Staleness detection (t-2001) ---
# Contract: stale pass runs unconditionally (even with no new entries);
# universe = enabled feeds.json entries (stale_after_days, default 14) + EXTRA_STALE_FEEDS;
# digest section "## ⚠ Stale feeds" with lines:
#   "- {name} — last entry {date} ({N}d ago, threshold {T}d)" | "- {name} — no entries yet"

FEEDS_JSON="$HOME/.claude/scheduler/feeds.json"
NOW_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
OLD_TS=$(date -u -d "30 days ago" +%Y-%m-%dT%H:%M:%SZ)
TEN_D_TS=$(date -u -d "10 days ago" +%Y-%m-%dT%H:%M:%SZ)

feed_entry() { # name, published
    printf '{"feed":"%s","title":"t","link":"https://example.com","published":"%s","polled_at":"%s"}\n' "$1" "$2" "$2"
}

# --- Test 6: Stale feed flagged, fresh feed not flagged ---
cat > "$FEEDS_JSON" <<'EOF'
[{"name":"stalefeed","url":"https://x/a.xml","action":"log","enabled":true},
 {"name":"freshfeed","url":"https://x/b.xml","action":"log","enabled":true}]
EOF
{ feed_entry stalefeed "$OLD_TS"; feed_entry freshfeed "$NOW_TS"; } > "$FEED_LOG"
rm -f "$WATERMARK" "$DIGEST"
output=$(bash "$SCRIPT" --force 2>&1); rc=$?
assert_pass "Staleness run exits 0" "$rc" "$output"
assert_file_contains "Stale section present" "$DIGEST" "Stale feeds"
assert_file_contains "Stale feed flagged" "$DIGEST" "stalefeed — last entry"
assert_not_contains "Fresh feed not flagged" "$(cat "$DIGEST")" "freshfeed — last entry"

# --- Test 7: Per-feed stale_after_days override respected ---
cat > "$FEEDS_JSON" <<'EOF'
[{"name":"slowfeed","url":"https://x/a.xml","action":"log","enabled":true,"stale_after_days":60},
 {"name":"fastfeed","url":"https://x/b.xml","action":"log","enabled":true,"stale_after_days":7}]
EOF
{ feed_entry slowfeed "$OLD_TS"; feed_entry fastfeed "$TEN_D_TS"; } > "$FEED_LOG"
rm -f "$WATERMARK" "$DIGEST"
bash "$SCRIPT" --force >/dev/null 2>&1
assert_not_contains "30d-old feed under 60d threshold not flagged" "$(cat "$DIGEST")" "slowfeed — last entry"
assert_file_contains "10d-old feed over 7d threshold flagged" "$DIGEST" "fastfeed — last entry"

# --- Test 8: Zero-entry registered feed reported as 'no entries yet' ---
cat > "$FEEDS_JSON" <<'EOF'
[{"name":"emptyfeed","url":"https://x/a.xml","action":"log","enabled":true},
 {"name":"freshfeed","url":"https://x/b.xml","action":"log","enabled":true}]
EOF
feed_entry freshfeed "$NOW_TS" > "$FEED_LOG"
rm -f "$WATERMARK" "$DIGEST"
bash "$SCRIPT" --force >/dev/null 2>&1
assert_file_contains "Zero-entry feed noted" "$DIGEST" "emptyfeed — no entries yet"

# --- Test 9: Stale section written even on a no-new-entries day ---
cat > "$FEEDS_JSON" <<'EOF'
[{"name":"stalefeed","url":"https://x/a.xml","action":"log","enabled":true}]
EOF
feed_entry stalefeed "$OLD_TS" > "$FEED_LOG"
rm -f "$DIGEST"
echo "1" > "$WATERMARK"   # fully consumed — zero new entries
output=$(bash "$SCRIPT" 2>&1); rc=$?
assert_pass "No-new-entries day exits 0" "$rc" "$output"
assert_file_contains "Stale section written despite no new entries" "$DIGEST" "stalefeed — last entry"

# --- Test 10: All feeds fresh → no stale section ---
cat > "$FEEDS_JSON" <<'EOF'
[{"name":"freshfeed","url":"https://x/a.xml","action":"log","enabled":true}]
EOF
feed_entry freshfeed "$NOW_TS" > "$FEED_LOG"
rm -f "$WATERMARK" "$DIGEST"
bash "$SCRIPT" --force >/dev/null 2>&1
assert_not_contains "No stale section when all fresh" "$(cat "$DIGEST")" "Stale feeds"

# --- Test 11: Disabled feed never flagged ---
cat > "$FEEDS_JSON" <<'EOF'
[{"name":"deadfeed","url":"https://x/a.xml","action":"log","enabled":false},
 {"name":"freshfeed","url":"https://x/b.xml","action":"log","enabled":true}]
EOF
feed_entry freshfeed "$NOW_TS" > "$FEED_LOG"
rm -f "$WATERMARK" "$DIGEST"
bash "$SCRIPT" --force >/dev/null 2>&1
assert_not_contains "Disabled feed not flagged" "$(cat "$DIGEST")" "deadfeed"

# --- Test 12: EXTRA_STALE_FEEDS (scraper feeds outside feeds.json) flagged ---
# kapso-changelog:21 is a script-level constant; 30d-old entry must flag.
cat > "$FEEDS_JSON" <<'EOF'
[{"name":"freshfeed","url":"https://x/a.xml","action":"log","enabled":true}]
EOF
{ feed_entry freshfeed "$NOW_TS"; feed_entry kapso-changelog "$OLD_TS"; } > "$FEED_LOG"
rm -f "$WATERMARK" "$DIGEST"
bash "$SCRIPT" --force >/dev/null 2>&1
assert_file_contains "Scraper feed past threshold flagged" "$DIGEST" "kapso-changelog — last entry"

# --- Test 13: Missing feeds.json → staleness pass degrades gracefully ---
rm -f "$FEEDS_JSON"
feed_entry freshfeed "$NOW_TS" > "$FEED_LOG"
rm -f "$WATERMARK" "$DIGEST"
output=$(bash "$SCRIPT" --force 2>&1); rc=$?
assert_pass "Missing feeds.json exits 0" "$rc" "$output"

# --- Summary ---
echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
