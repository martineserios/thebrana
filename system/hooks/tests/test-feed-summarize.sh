#!/usr/bin/env bash
# Tests for feed-summarize.sh
# Stubs the claude binary; article URLs are file:// paths so fetch_and_strip
# needs no network. Covers the per-run cap (t-2076): a capped run exits 0,
# leaves the watermark untouched, and later runs drain the backlog via the
# link-dedup set.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../../scripts/feed-summarize.sh"
PASS=0
FAIL=0
TOTAL=0
TMPDIR=$(mktemp -d)

trap 'rm -rf "$TMPDIR"' EXIT

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

echo "Feed Summarize Tests"
echo "===================="

# --- Setup: isolated state, stub claude, local file:// articles ---
export HOME="$TMPDIR/home"
mkdir -p "$HOME/.claude/scheduler/state"

export FEED_LOG="$TMPDIR/feed-log.jsonl"
export SUMMARIES="$TMPDIR/feed-summaries.jsonl"
export WATERMARK="$TMPDIR/feed-summarize-watermark"

STUB_CLAUDE="$TMPDIR/claude"
cat > "$STUB_CLAUDE" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
echo "Stub summary: model release with new capabilities."
EOF
chmod +x "$STUB_CLAUDE"
export CLAUDE_BIN="$STUB_CLAUDE"

make_article() {
    local path="$1" title="$2"
    {
        printf '<html><head><title>%s</title></head><body><p>' "$title"
        printf 'This is a sufficiently long article body about %s. ' "$title"
        head -c 300 /dev/zero | tr '\0' 'a'
        printf '</p></body></html>'
    } > "$path"
}

make_article "$TMPDIR/a1.html" "Post One"
make_article "$TMPDIR/a2.html" "Post Two"
make_article "$TMPDIR/a3.html" "Post Three"

entry() {
    printf '{"feed":"anthropic-news","title":"%s","link":"file://%s","published":"2026-06-12T10:00:00Z","polled_at":"2026-06-12T10:00:00Z"}\n' "$1" "$2"
}

{
    entry "Post One"   "$TMPDIR/a1.html"
    entry "Post Two"   "$TMPDIR/a2.html"
    entry "Post Three" "$TMPDIR/a3.html"
} > "$FEED_LOG"

# --- Test 1: capped run summarizes up to the cap and exits 0 ---
rm -f "$WATERMARK" "$SUMMARIES"
output=$(FEED_SUMMARIZE_MAX=1 bash "$SCRIPT" 2>&1); rc=$?
assert_eq "capped run exits 0" "0" "$rc"
assert_eq "capped run summarized exactly 1" "1" "$(wc -l < "$SUMMARIES" | tr -d ' ')"
assert_contains "capped run reports the cap" "$output" "cap"

# --- Test 2: capped run leaves the watermark untouched ---
assert_eq "capped run does not advance watermark" "absent" "$([ -f "$WATERMARK" ] && cat "$WATERMARK" || echo absent)"

# --- Test 3: next capped run drains the next entry via link dedup ---
output=$(FEED_SUMMARIZE_MAX=1 bash "$SCRIPT" 2>&1); rc=$?
assert_eq "second capped run exits 0" "0" "$rc"
assert_eq "second capped run appends one more" "2" "$(wc -l < "$SUMMARIES" | tr -d ' ')"
assert_eq "summaries cover distinct links" "2" "$(jq -r '.link' "$SUMMARIES" | sort -u | wc -l | tr -d ' ')"

# --- Test 4: uncapped run drains the rest and advances the watermark ---
output=$(bash "$SCRIPT" 2>&1); rc=$?
assert_eq "draining run exits 0" "0" "$rc"
assert_eq "all entries summarized" "3" "$(wc -l < "$SUMMARIES" | tr -d ' ')"
assert_eq "watermark advances after full drain" "3" "$(cat "$WATERMARK" 2>/dev/null | tr -d ' ' || echo missing)"

# --- Test 5: subsequent run is a no-op ---
output=$(bash "$SCRIPT" 2>&1); rc=$?
assert_eq "no-op run exits 0" "0" "$rc"
assert_contains "no-op run reports no new entries" "$output" "No new entries"

# --- Summary ---
echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
