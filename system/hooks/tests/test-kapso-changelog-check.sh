#!/usr/bin/env bash
# Tests for kapso-changelog-check.sh (t-2011)
# Fixture-based — no network. Verifies parse, dedup state, dry-run, failure guard.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../../scripts/kapso-changelog-check.sh"
PASS=0
FAIL=0
TOTAL=0
TMPDIR=$(mktemp -d)

trap 'rm -rf "$TMPDIR"' EXIT

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
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
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected output to contain: $pattern"
        echo "    got: $output"
        FAIL=$((FAIL + 1))
    fi
}

echo "Kapso Changelog Check Tests"
echo "==========================="

export HOME="$TMPDIR/home"
mkdir -p "$HOME/.claude/scheduler/state"
FEED_LOG="$HOME/.claude/scheduler/feed-log.jsonl"
STATE="$HOME/.claude/scheduler/state/kapso-changelog-scrape.json"

FIXTURE="$TMPDIR/changelog.md"
cat > "$FIXTURE" <<'EOF'
# Changelog

> Product updates and announcements

<Update label="Jun 9, 2026">
  ## API changes

  **WhatsApp carousel message support**: Kapso now preserves carousel payloads.

  ## Bug fixes

  **Template header variables**: Fixed rendering issue.
</Update>

<Update label="May 26, 2026">
  ## Features

  **Per-project audio transcription toggle**: New project setting.
</Update>
EOF

# --- Test 1: dry-run parses fixture, prints 2 entries, writes nothing ---
rm -f "$FEED_LOG" "$STATE"
output=$(bash "$SCRIPT" --source "$FIXTURE" --dry-run 2>&1); rc=$?
assert_eq "Dry-run exits 0" "0" "$rc"
assert_contains "Dry-run reports 2 new updates" "$output" "2 new"
assert_eq "Dry-run does not write feed-log" "absent" "$([ -f "$FEED_LOG" ] && echo present || echo absent)"
assert_eq "Dry-run does not write state" "absent" "$([ -f "$STATE" ] && echo present || echo absent)"

# --- Test 2: real run appends valid FeedLogEntry JSONL + writes state ---
rm -f "$FEED_LOG" "$STATE"
output=$(bash "$SCRIPT" --source "$FIXTURE" 2>&1); rc=$?
assert_eq "Real run exits 0" "0" "$rc"
assert_eq "Two lines appended" "2" "$(wc -l < "$FEED_LOG" | tr -d ' ')"
assert_eq "All lines valid JSON" "2" "$(jq -c . "$FEED_LOG" 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "feed field correct" "kapso-changelog" "$(head -1 "$FEED_LOG" | jq -r .feed)"
# Entries append oldest-first (chronological log) — newest is the LAST line
assert_contains "published is ISO date (newest = last line)" "$(tail -1 "$FEED_LOG" | jq -r .published)" "2026-06-09"
assert_contains "title nonempty" "$(tail -1 "$FEED_LOG" | jq -r .title)" "."
assert_contains "content carries update body" "$(tail -1 "$FEED_LOG" | jq -r .content)" "carousel"
assert_eq "State file written" "present" "$([ -f "$STATE" ] && echo present || echo absent)"

# --- Test 3: second run with same fixture is a no-op (dedup via state) ---
output=$(bash "$SCRIPT" --source "$FIXTURE" 2>&1); rc=$?
assert_eq "Second run exits 0" "0" "$rc"
assert_contains "Second run reports no new updates" "$output" "0 new"
assert_eq "No additional lines appended" "2" "$(wc -l < "$FEED_LOG" | tr -d ' ')"

# --- Test 4: new update in fixture → only the new one appended ---
cat > "$FIXTURE.v2" <<'EOF'
# Changelog

<Update label="Jun 15, 2026">
  ## Features

  **Flow versioning**: Workflows now support draft/published versions.
</Update>

<Update label="Jun 9, 2026">
  ## API changes

  **WhatsApp carousel message support**: Kapso now preserves carousel payloads.
</Update>

<Update label="May 26, 2026">
  ## Features

  **Per-project audio transcription toggle**: New project setting.
</Update>
EOF
output=$(bash "$SCRIPT" --source "$FIXTURE.v2" 2>&1); rc=$?
assert_eq "Incremental run exits 0" "0" "$rc"
assert_contains "One new update detected" "$output" "1 new"
assert_eq "Three lines total" "3" "$(wc -l < "$FEED_LOG" | tr -d ' ')"
assert_contains "New entry is the Jun 15 one" "$(tail -1 "$FEED_LOG" | jq -r .published)" "2026-06-15"

# --- Test 5: fetch failure guard — missing source exits 1, state untouched ---
cp "$STATE" "$TMPDIR/state-before.json"
output=$(bash "$SCRIPT" --source "$TMPDIR/does-not-exist.md" 2>&1); rc=$?
assert_eq "Missing source exits 1" "1" "$rc"
assert_contains "Failure is explicit" "$output" "FETCH FAILED"
assert_eq "State untouched on failure" "$(cat "$TMPDIR/state-before.json")" "$(cat "$STATE")"

# --- Summary ---
echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
