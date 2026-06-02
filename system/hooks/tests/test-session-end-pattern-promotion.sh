#!/usr/bin/env bash
# Tests for session-end-pattern-promotion.sh
# Uses fake HOME and fake ruflo binary to avoid real network calls.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../session-end-pattern-promotion.sh"
PASS=0
FAIL=0
TOTAL=0

TMPDIR_T=$(mktemp -d)
trap 'rm -rf "$TMPDIR_T"' EXIT

# Fake HOME with stub cf-env.sh pointing to mock ruflo
export HOME="$TMPDIR_T"
mkdir -p "$TMPDIR_T/.claude/scripts" "$TMPDIR_T/.claude/logs"

# Create mock ruflo binary that records calls
MOCK_CF="$TMPDIR_T/mock-ruflo"
cat > "$MOCK_CF" <<'MOCK'
#!/usr/bin/env bash
# Mock ruflo — records calls to a log file, returns empty JSON for searches
MOCK_LOG="${RUFLO_MOCK_LOG:-/tmp/ruflo-mock-calls.log}"
echo "$@" >> "$MOCK_LOG"
if echo "$@" | grep -q "memory search"; then
    echo "[]"
fi
exit 0
MOCK
chmod +x "$MOCK_CF"

cat > "$TMPDIR_T/.claude/scripts/cf-env.sh" <<EOF
export CF="$MOCK_CF"
EOF

MOCK_LOG="$TMPDIR_T/ruflo-calls.log"
export RUFLO_MOCK_LOG="$MOCK_LOG"

make_session_file() {
    local path="$1" keys_json="${2:-[]}"
    printf '{"ts":1000,"tool":"session-start","outcome":"recall","detail":"some patterns","keys":%s}\n' "$keys_json" > "$path"
}

assert_eq() {
    local desc="$1" got="$2" want="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$got" = "$want" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — got '$got', want '$want'"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_contains() {
    local desc="$1" file="$2" pattern="$3"
    TOTAL=$((TOTAL + 1))
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — pattern '$pattern' not found in $file"
        FAIL=$((FAIL + 1))
    fi
}

# ── Test 1: no session file → exits 0 immediately ────────────────────────────
echo "Test 1: no session file → exits cleanly"
TOTAL=$((TOTAL + 1))
SESSION_FILE="/tmp/nonexistent-session-$$" \
CORRECTION_RATE="0.00" CORRECTIONS="0" TOTAL="20" PROJECT="test" \
    bash "$HOOK" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "  PASS: no session file → exit 0"
    PASS=$((PASS + 1))
else
    echo "  FAIL: unexpected non-zero exit"
    FAIL=$((FAIL + 1))
fi

# ── Test 2: total < 10 → no action ──────────────────────────────────────────
echo "Test 2: total < 10 → no-op"
SF="$TMPDIR_T/session-low.jsonl"
make_session_file "$SF" '["pattern:proj:key1"]'
rm -f "$MOCK_LOG"
SESSION_FILE="$SF" CORRECTION_RATE="0.00" CORRECTIONS="0" TOTAL="5" PROJECT="proj" \
    bash "$HOOK" 2>/dev/null
CALLS=$(wc -l < "$MOCK_LOG" 2>/dev/null || echo 0)
assert_eq "total<10 → no ruflo calls" "$CALLS" "0"

# ── Test 3: rate between thresholds → no-op ──────────────────────────────────
echo "Test 3: rate between thresholds (0.12) → no-op"
SF="$TMPDIR_T/session-mid.jsonl"
make_session_file "$SF" '["pattern:proj:key2"]'
rm -f "$MOCK_LOG"
SESSION_FILE="$SF" CORRECTION_RATE="0.12" CORRECTIONS="2" TOTAL="17" PROJECT="proj" \
    bash "$HOOK" 2>/dev/null
CALLS=$(wc -l < "$MOCK_LOG" 2>/dev/null || echo 0)
assert_eq "rate 0.12 → no ruflo calls" "$CALLS" "0"

# ── Test 4: clean session → promote action logged ────────────────────────────
echo "Test 4: clean session (rate 0.02) → promote logged"
SF="$TMPDIR_T/session-clean.jsonl"
make_session_file "$SF" '["pattern:proj:key3","pattern:proj:key4"]'
rm -f "$MOCK_LOG"
SESSION_FILE="$SF" CORRECTION_RATE="0.02" CORRECTIONS="0" TOTAL="15" PROJECT="proj" \
    bash "$HOOK" 2>/dev/null
# Promotion log should exist and contain "promote"
assert_file_contains "promote logged to audit file" \
    "$TMPDIR_T/.claude/logs/pattern-promotion.jsonl" '"action":"promote"'

# ── Test 5: bad session → demote action logged ───────────────────────────────
echo "Test 5: high correction rate (0.30) → demote logged"
SF="$TMPDIR_T/session-bad.jsonl"
make_session_file "$SF" '["pattern:proj:key5"]'
SESSION_FILE="$SF" CORRECTION_RATE="0.30" CORRECTIONS="5" TOTAL="17" PROJECT="proj" \
    bash "$HOOK" 2>/dev/null
assert_file_contains "demote logged to audit file" \
    "$TMPDIR_T/.claude/logs/pattern-promotion.jsonl" '"action":"demote"'

# ── Test 6: no recalled keys → exits without calling ruflo ───────────────────
echo "Test 6: recall event with empty keys → no ruflo store calls"
SF="$TMPDIR_T/session-nokeys.jsonl"
printf '{"ts":1000,"tool":"session-start","outcome":"recall","detail":"patterns","keys":[]}\n' > "$SF"
rm -f "$MOCK_LOG"
SESSION_FILE="$SF" CORRECTION_RATE="0.01" CORRECTIONS="0" TOTAL="20" PROJECT="proj" \
    bash "$HOOK" 2>/dev/null
STORE_CALLS=$(grep -c "memory store" "$MOCK_LOG" 2>/dev/null || echo 0)
assert_eq "no keys → no store calls" "$STORE_CALLS" "0"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
