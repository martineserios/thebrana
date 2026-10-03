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


# ── Tests 7-13: a failed or empty READ must never become a WRITE (t-3455) ─────────────
# The real CLI: `memory retrieve -k KEY --format json` prints noise lines, then ONE JSON object on
# a hit whose .content is the stored value (object, or a JSON-encoded string), or
# "[WARN] Key not found: KEY" with rc 0 on a clean miss. `memory search --format json` returns
# {results:[{key,score,preview}]} with no value — the hook must not use it as a read.
MOCK_CF2="$TMPDIR_T/mock-ruflo-modes"
cat > "$MOCK_CF2" <<'MOCK'
#!/usr/bin/env bash
MOCK_LOG="${RUFLO_MOCK_LOG:-/tmp/ruflo-mock-calls.log}"
echo "$@" >> "$MOCK_LOG"
if echo "$@" | grep -q "memory retrieve"; then
    KEY=$(echo "$@" | sed -n 's/.*-k \([^ ]*\).*/\1/p')
    echo "Transformers.js loaded: Xenova/all-MiniLM-L6-v2"      # noise line precedes the JSON, as live
    case "${MOCK_SEARCH_MODE:-missing}" in
        ceiling)  exit 124 ;;                                   # the shim ceiling fired
        error)    echo "boom" >&2; exit 127 ;;                  # CF missing / crashed
        garbage)  echo "not json at all"; exit 0 ;;             # rc 0, no JSON, no WARN
        wrongkey) printf '{"key":"pattern:other:key","namespace":"pattern","content":{"problem":"other"}}\n'; exit 0 ;;
        found)    printf '{"key":"%s","namespace":"pattern","content":"{\\"problem\\":\\"orig-problem\\",\\"confidence\\":0.5,\\"recall_count\\":1}"}\n' "$KEY"; exit 0 ;;
        found2)   printf '{"key":"%s","namespace":"pattern","content":"\\"{\\\\\\"problem\\\\\\":\\\\\\"orig-problem\\\\\\",\\\\\\"confidence\\\\\\":0.5}\\""}\n' "$KEY"; exit 0 ;;
        foundobj) printf '{"key":"%s","namespace":"pattern","content":{"problem":"orig-problem","confidence":0.5,"recall_count":1}}\n' "$KEY"; exit 0 ;;
        text)     printf '{"key":"%s","namespace":"pattern","content":"plain prose, not json"}\n' "$KEY"; exit 0 ;;
        missing)  echo "[WARN] Key not found: $KEY"; exit 0 ;;
    esac
fi
if echo "$@" | grep -q "memory search"; then echo '{"query":"x","results":[],"searchTime":"1ms"}'; fi
exit 0
MOCK
chmod +x "$MOCK_CF2"
cat > "$TMPDIR_T/.claude/scripts/cf-env.sh" <<EOF
export CF="$MOCK_CF2"
EOF

run_mode() {  # run_mode MODE KEY → runs a clean promote session with one recalled key
    local mode="$1" key="$2" sf; sf="$TMPDIR_T/session-$mode.jsonl"
    make_session_file "$sf" "[\"$key\"]"
    rm -f "$MOCK_LOG"
    MOCK_SEARCH_MODE="$mode" SESSION_FILE="$sf" CORRECTION_RATE="0.01" CORRECTIONS="0" TOTAL="20" PROJECT="proj" \
        bash "$HOOK" 2>/dev/null
}
store_calls() { local n; n=$(grep -c "memory store" "$MOCK_LOG" 2>/dev/null); echo "${n:-0}"; }   # grep -c prints 0 AND exits 1 on no match
last_audit() { tail -1 "$TMPDIR_T/.claude/logs/pattern-promotion.jsonl" 2>/dev/null; }

echo "Test 7: read hits the shim ceiling (rc 124) → NO store (must-fire)"
run_mode ceiling "pattern:proj:key7"
assert_eq "ceiling read → zero store calls" "$(store_calls)" "0"
assert_file_contains "ceiling read counted as skipped_unreadable" "$TMPDIR_T/.claude/logs/pattern-promotion.jsonl" '"skipped_unreadable":1'

echo "Test 8: read exits 127 → NO store"
run_mode error "pattern:proj:key8"
assert_eq "errored read → zero store calls" "$(store_calls)" "0"

echo "Test 9: rc 0 but no JSON and no WARN → NO store"
run_mode garbage "pattern:proj:key9"
assert_eq "garbage read → zero store calls" "$(store_calls)" "0"

echo "Test 10: JSON for a different key → NO store"
run_mode wrongkey "pattern:proj:key10"
assert_eq "wrong-key read → zero store calls" "$(store_calls)" "0"

echo "Test 11: entry found, content is a JSON-encoded string → merged store keeps original fields"
run_mode found "pattern:proj:key11"
assert_eq "found entry → exactly one store call" "$(store_calls)" "1"
assert_file_contains "stored value keeps original problem field" "$MOCK_LOG" 'orig-problem'
assert_file_contains "stored value carries updated confidence" "$MOCK_LOG" '"confidence":0.6'
assert_file_contains "store is an explicit upsert" "$MOCK_LOG" '[-]-upsert'
assert_eq "hook never uses memory search as a read" "$(grep -c 'memory search' "$MOCK_LOG" 2>/dev/null || true)" "0"

echo "Test 12: entry found, content double-encoded (live row shape) and as a bare object → both merge"
run_mode found2 "pattern:proj:key12"
assert_eq "double-encoded content → one store call" "$(store_calls)" "1"
assert_file_contains "double-encoded content survives the merge" "$MOCK_LOG" 'orig-problem'
run_mode foundobj "pattern:proj:key12b"
assert_eq "object content → one store call" "$(store_calls)" "1"
assert_file_contains "object content survives the merge" "$MOCK_LOG" 'orig-problem'

echo "Test 13: clean miss (WARN Key not found, rc 0) and non-JSON content → NO store, counted"
run_mode missing "pattern:proj:key13"
assert_eq "clean miss → zero store calls (no placeholder, ever)" "$(store_calls)" "0"
assert_file_contains "clean miss counted as missing" "$TMPDIR_T/.claude/logs/pattern-promotion.jsonl" '"missing":1'
run_mode text "pattern:proj:key13b"
assert_eq "prose content → zero store calls" "$(store_calls)" "0"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
