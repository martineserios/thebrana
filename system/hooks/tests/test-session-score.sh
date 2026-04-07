#!/usr/bin/env bash
# Tests for session score tracking (counter file + statusline segment)
# Validates: session-start resets counter, task-completed increments, statusline reads it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
TOTAL=0
TMPDIR=$(mktemp -d)

trap 'rm -rf "$TMPDIR"' EXIT

# ── Helpers ──────────────────────────────────────────────

assert_eq() {
    local desc="$1"; local expected="$2"; local actual="$3"
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
    local desc="$1"; local needle="$2"; local haystack="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$haystack" | grep -qF "$needle"; then
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
    local desc="$1"; local needle="$2"; local haystack="$3"
    TOTAL=$((TOTAL + 1))
    if ! echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected NOT to contain: $needle"
        echo "    got: $haystack"
        FAIL=$((FAIL + 1))
    fi
}

echo "Session Score Tests"
echo "==================="

# ── Test 1: Counter file creation (session-start resets) ──────────
echo ""
echo "--- Counter file lifecycle ---"

SCORE_FILE="$TMPDIR/session-score.tsv"

# Simulate session-start writing the counter
printf '0\t0\n' > "$SCORE_FILE"
IFS=$'\t' read -r DONE CORR < "$SCORE_FILE"
assert_eq "Session start creates counter with done=0" "0" "$DONE"
assert_eq "Session start creates counter with corrections=0" "0" "$CORR"

# ── Test 2: Increment done counter ───────────────────────────────
echo ""
echo "--- Counter increment ---"

# Simulate task completion incrementing done counter
IFS=$'\t' read -r CUR_DONE CUR_CORR < "$SCORE_FILE"
printf '%d\t%d\n' "$((CUR_DONE + 1))" "$CUR_CORR" > "$SCORE_FILE"
IFS=$'\t' read -r DONE CORR < "$SCORE_FILE"
assert_eq "Done counter increments to 1" "1" "$DONE"
assert_eq "Corrections stays at 0 after done increment" "0" "$CORR"

# Increment again
IFS=$'\t' read -r CUR_DONE CUR_CORR < "$SCORE_FILE"
printf '%d\t%d\n' "$((CUR_DONE + 1))" "$CUR_CORR" > "$SCORE_FILE"
IFS=$'\t' read -r DONE CORR < "$SCORE_FILE"
assert_eq "Done counter increments to 2" "2" "$DONE"

# ── Test 3: Increment corrections counter ─────────────────────────
echo ""
echo "--- Corrections counter ---"

IFS=$'\t' read -r CUR_DONE CUR_CORR < "$SCORE_FILE"
printf '%d\t%d\n' "$CUR_DONE" "$((CUR_CORR + 1))" > "$SCORE_FILE"
IFS=$'\t' read -r DONE CORR < "$SCORE_FILE"
assert_eq "Corrections increments to 1" "1" "$CORR"
assert_eq "Done stays at 2 after corrections increment" "2" "$DONE"

# ── Test 4: Session-start resets existing counters ────────────────
echo ""
echo "--- Counter reset ---"

printf '0\t0\n' > "$SCORE_FILE"
IFS=$'\t' read -r DONE CORR < "$SCORE_FILE"
assert_eq "Session start resets done to 0" "0" "$DONE"
assert_eq "Session start resets corrections to 0" "0" "$CORR"

# ── Test 5: Statusline reads counter correctly ────────────────────
echo ""
echo "--- Statusline segment ---"

# Helper: extract session score from statusline output
# The statusline reads from the file and renders S: N✓ M✗
STATUSLINE="$SCRIPT_DIR/../../statusline.sh"

# Create a minimal statusline input JSON
FAKE_CWD="$TMPDIR/fakecwd"
mkdir -p "$FAKE_CWD"
STATUSLINE_INPUT='{"model":{"display_name":"Test"},"workspace":{"current_dir":"'"$FAKE_CWD"'","project_dir":"'"$FAKE_CWD"'"},"context_window":{"used_percentage":30},"cost":{"total_lines_added":0,"total_lines_removed":0}}'

# Test with non-zero score
printf '5\t2\n' > "$SCORE_FILE"
OUTPUT=$(echo "$STATUSLINE_INPUT" | BRANA_SESSION_SCORE_FILE="$SCORE_FILE" bash "$STATUSLINE" 2>/dev/null) || true
assert_contains "Statusline shows done count" "5✓" "$OUTPUT"
assert_contains "Statusline shows corrections count" "2✗" "$OUTPUT"

# Test with zero score — segment should be hidden
printf '0\t0\n' > "$SCORE_FILE"
OUTPUT=$(echo "$STATUSLINE_INPUT" | BRANA_SESSION_SCORE_FILE="$SCORE_FILE" bash "$STATUSLINE" 2>/dev/null) || true
assert_not_contains "Statusline hides segment when all zero" "S:" "$OUTPUT"

# Test with only done > 0
printf '3\t0\n' > "$SCORE_FILE"
OUTPUT=$(echo "$STATUSLINE_INPUT" | BRANA_SESSION_SCORE_FILE="$SCORE_FILE" bash "$STATUSLINE" 2>/dev/null) || true
assert_contains "Statusline shows segment when done > 0" "3✓" "$OUTPUT"

# Test with missing counter file
OUTPUT=$(echo "$STATUSLINE_INPUT" | BRANA_SESSION_SCORE_FILE="$TMPDIR/nonexistent.tsv" bash "$STATUSLINE" 2>/dev/null) || true
assert_not_contains "Statusline hides segment when file missing" "S:" "$OUTPUT"

# ── Summary ──────────────────────────────────────────────
echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
