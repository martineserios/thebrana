#!/usr/bin/env bash
# Tests: validate.sh Check 51 — hooks.json entries must use command:string not args:[] (t-1787)
# Verifies the schema guard catches entries that use the deprecated args field format
# and passes clean files that only use command strings.

set -uo pipefail

PASS=0; FAIL=0; TOTAL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

assert_eq() {
    local desc="$1" got="$2" expected="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$got" = "$expected" ]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected: $expected"
        echo "    got:      $got"
        FAIL=$((FAIL + 1))
    fi
}

# The jq expression used by Check 51
ARGS_COUNT_JQ='[.hooks // {} | .[][] | .hooks[]? | select(.args != null)] | length'

echo "Validate hooks.json Command Schema Tests"
echo "========================================="
echo ""

# ── Test 1: clean file — all entries use command string ───────────────────
echo "--- Clean file (command:string only) ---"
CLEAN="$TMPDIR/hooks-clean.json"
cat > "$CLEAN" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "hooks": [
          { "type": "command", "command": "bash \"$HOME/.claude/hooks/pre-tool-use.sh\"", "timeout": 5000 }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          { "type": "command", "command": "bash \"$HOME/.claude/hooks/post-tool-use.sh\"", "timeout": 5000 }
        ]
      }
    ]
  }
}
JSON

COUNT=$(jq "$ARGS_COUNT_JQ" "$CLEAN")
assert_eq "clean file has 0 args-field entries" "$COUNT" "0"

# ── Test 2: file with args field — old/invalid format ─────────────────────
echo ""
echo "--- File with args field (invalid format) ---"
BAD="$TMPDIR/hooks-bad.json"
cat > "$BAD" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "hooks": [
          { "type": "command", "args": ["bash", "$HOME/.claude/hooks/pre-tool-use.sh"], "timeout": 5000 },
          { "type": "command", "command": "bash \"$HOME/.claude/hooks/another.sh\"", "timeout": 5000 }
        ]
      }
    ]
  }
}
JSON

COUNT=$(jq "$ARGS_COUNT_JQ" "$BAD")
assert_eq "file with args field has 1 invalid entry" "$COUNT" "1"

# ── Test 3: multiple invalid entries ──────────────────────────────────────
echo ""
echo "--- Multiple invalid entries ---"
MULTI="$TMPDIR/hooks-multi-bad.json"
cat > "$MULTI" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "hooks": [
          { "type": "command", "args": ["bash", "hook-a.sh"] },
          { "type": "command", "args": ["bash", "hook-b.sh"] }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          { "type": "command", "command": "bash \"$HOME/.claude/hooks/valid.sh\"" }
        ]
      }
    ]
  }
}
JSON

COUNT=$(jq "$ARGS_COUNT_JQ" "$MULTI")
assert_eq "file with 2 args entries reports count 2" "$COUNT" "2"

# ── Test 4: empty hooks object — no false positive ─────────────────────────
echo ""
echo "--- Empty hooks object ---"
EMPTY="$TMPDIR/hooks-empty.json"
cat > "$EMPTY" <<'JSON'
{ "hooks": {} }
JSON

COUNT=$(jq "$ARGS_COUNT_JQ" "$EMPTY")
assert_eq "empty hooks object has 0 invalid entries" "$COUNT" "0"

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
