#!/usr/bin/env bash
# Tests: pending-reminder count surfacing in session-start.sh (t-1967, ADR-051 §3).
# Pure jq read of ~/.claude/reminders.json — silent when file missing, empty,
# corrupt, or count is 0. Never blocks startup.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../session-start.sh"
PASS=0
FAIL=0
TOTAL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

SAFE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
GIT_BIN="$(dirname "$(command -v git)")"
JQ_BIN="$(dirname "$(command -v jq)")"
[[ ":$SAFE_PATH:" != *":$GIT_BIN:"* ]] && SAFE_PATH="$GIT_BIN:$SAFE_PATH"
[[ ":$SAFE_PATH:" != *":$JQ_BIN:"* ]] && SAFE_PATH="$JQ_BIN:$SAFE_PATH"

# ── Helpers ──────────────────────────────────────────────

setup_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main 2>/dev/null || git -C "$dir" init -q
    git -C "$dir" config user.email "test@test.com"
    git -C "$dir" config user.name "Test"
    echo "init" > "$dir/README.md"
    git -C "$dir" add -A && git -C "$dir" commit -q -m "init" 2>/dev/null
}

make_home() {
    local home="$1"
    mkdir -p "$home/.claude/projects/fake/memory"
    echo "# Memory" > "$home/.claude/projects/fake/memory/MEMORY.md"
}

write_store() {
    local home="$1" body="$2"
    mkdir -p "$home/.claude"
    printf '%s' "$body" > "$home/.claude/reminders.json"
}

run_hook() {
    local cwd="$1" home="$2"
    local input
    input=$(printf '{"session_id":"remind-test-%s","cwd":"%s","hook_event_name":"SessionStart","matcher":{}}' \
        "$(date +%s)" "$cwd")
    echo "$input" | \
        PATH="$SAFE_PATH" \
        HOME="$home" \
        CLAUDE_PLUGIN_DATA="" CLAUDE_PLUGIN_ROOT="" CLAUDE_ENV_FILE="" \
        BRANA_RECAP_OFF=1 BRANA_1M_WARN_OFF=1 BRANA_HOOK_PROFILE=standard \
        bash "$HOOK" 2>/dev/null | grep -E '^\{' | head -1
}

assert_context_contains() {
    local desc="$1" pattern="$2" output="$3"
    TOTAL=$((TOTAL + 1))
    local ctx
    ctx=$(echo "$output" | jq -r '.additionalContext // ""' 2>/dev/null)
    if echo "$ctx" | grep -qi "$pattern"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected context to contain: $pattern"
        FAIL=$((FAIL + 1))
    fi
}

assert_context_missing() {
    local desc="$1" pattern="$2" output="$3"
    TOTAL=$((TOTAL + 1))
    local ctx
    ctx=$(echo "$output" | jq -r '.additionalContext // ""' 2>/dev/null)
    if echo "$ctx" | grep -qi "$pattern"; then
        echo "  FAIL: $desc"
        echo "    expected context NOT to contain: $pattern"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    fi
}

# ── Tests ────────────────────────────────────────────────
echo "Reminder Count Surfacing Tests"
echo "=============================="
echo ""

REPO="$TMPDIR/repo"
setup_repo "$REPO"

# 1. Two pending (one high) + one resolved → "2 pending (1 high)"
H1="$TMPDIR/home1"; make_home "$H1"
write_store "$H1" '{"version":1,"reminders":[
  {"id":"r-1","text":"a","priority":"high","status":"pending"},
  {"id":"r-2","text":"b","priority":"medium","status":"pending"},
  {"id":"r-3","text":"c","priority":"high","status":"resolved"}]}'
OUT=$(run_hook "$REPO" "$H1")
assert_context_contains "pending count surfaces" "Reminders: 2 pending" "$OUT"
assert_context_contains "high count surfaces" "(1 high)" "$OUT"
assert_context_contains "mentions brana remind list" "brana remind list" "$OUT"

# 2. Zero pending (all resolved) → silent
H2="$TMPDIR/home2"; make_home "$H2"
write_store "$H2" '{"version":1,"reminders":[{"id":"r-1","text":"a","priority":"low","status":"resolved"}]}'
OUT=$(run_hook "$REPO" "$H2")
assert_context_missing "zero pending is silent" "Reminders:" "$OUT"

# 3. Missing file → silent
H3="$TMPDIR/home3"; make_home "$H3"
OUT=$(run_hook "$REPO" "$H3")
assert_context_missing "missing store is silent" "Reminders:" "$OUT"

# 4. Empty file → silent (and hook still emits valid JSON)
H4="$TMPDIR/home4"; make_home "$H4"
write_store "$H4" ''
OUT=$(run_hook "$REPO" "$H4")
assert_context_missing "empty store is silent" "Reminders:" "$OUT"
TOTAL=$((TOTAL + 1))
if echo "$OUT" | jq -e '.continue == true' >/dev/null 2>&1; then
    echo "  PASS: hook output is valid JSON with empty store"
    PASS=$((PASS + 1))
else
    echo "  FAIL: hook output is valid JSON with empty store"
    FAIL=$((FAIL + 1))
fi

# 5. Corrupt JSON → silent, hook never blocks
H5="$TMPDIR/home5"; make_home "$H5"
write_store "$H5" '{not json'
OUT=$(run_hook "$REPO" "$H5")
assert_context_missing "corrupt store is silent" "Reminders:" "$OUT"
TOTAL=$((TOTAL + 1))
if echo "$OUT" | jq -e '.continue == true' >/dev/null 2>&1; then
    echo "  PASS: hook output is valid JSON with corrupt store"
    PASS=$((PASS + 1))
else
    echo "  FAIL: hook output is valid JSON with corrupt store"
    FAIL=$((FAIL + 1))
fi

# 6. No high-priority pending → no "(0 high)" noise
H6="$TMPDIR/home6"; make_home "$H6"
write_store "$H6" '{"version":1,"reminders":[{"id":"r-1","text":"a","priority":"medium","status":"pending"}]}'
OUT=$(run_hook "$REPO" "$H6")
assert_context_contains "single pending surfaces" "Reminders: 1 pending" "$OUT"
assert_context_missing "no zero-high suffix" "(0 high)" "$OUT"

echo ""
echo "test-reminder-count: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
