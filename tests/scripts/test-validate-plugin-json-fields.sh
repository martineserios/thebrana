#!/usr/bin/env bash
# Tests for validate.sh Check 35 — system/plugin.json required fields (t-1753/t-1757).
#
# Directly tests the jq field-presence logic used by Check 35 rather than running
# the full validate.sh (which would test the live system/plugin.json, not edge cases).
#
# Rule: system/plugin.json must have both "skills" and "commands" fields.
# Without them, Skill() routing fails silently even though available-skills
# system-reminder is still populated via SKILL.md scanning.

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# Reproduce the exact jq logic from Check 35
check35_missing_fields() {
    local plugin_json="$1"
    local missing=()
    jq -e '.skills'   "$plugin_json" > /dev/null 2>&1 || missing+=("skills")
    jq -e '.commands' "$plugin_json" > /dev/null 2>&1 || missing+=("commands")
    echo "${missing[*]:-}"
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected '$expected', got '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

assert_empty() {
    local desc="$1" result="$2"
    TOTAL=$((TOTAL + 1))
    if [ -z "$result" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected no missing fields, got: '$result'"
        FAIL=$((FAIL + 1))
    fi
}

assert_nonempty() {
    local desc="$1" result="$2"
    TOTAL=$((TOTAL + 1))
    if [ -n "$result" ]; then
        echo "  PASS: $desc (missing: $result)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected missing fields but found none"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Check 35: system/plugin.json required fields (t-1753) ==="
echo ""

# ── Test 1: Missing both skills and commands → both reported ──────────────────
echo "Test 1: plugin.json missing both 'skills' and 'commands'"
cat > "$TMPROOT/plugin-no-fields.json" << 'EOF'
{
  "name": "brana",
  "version": "1.0.0"
}
EOF
result=$(check35_missing_fields "$TMPROOT/plugin-no-fields.json")
assert_nonempty "both fields missing → detected" "$result"
# Both should be in the list
if [[ "$result" == *"skills"* ]]; then
    TOTAL=$((TOTAL + 1)); echo "  PASS: 'skills' in missing list"; PASS=$((PASS + 1))
else
    TOTAL=$((TOTAL + 1)); echo "  FAIL: 'skills' not in missing list (got: '$result')"; FAIL=$((FAIL + 1))
fi
if [[ "$result" == *"commands"* ]]; then
    TOTAL=$((TOTAL + 1)); echo "  PASS: 'commands' in missing list"; PASS=$((PASS + 1))
else
    TOTAL=$((TOTAL + 1)); echo "  FAIL: 'commands' not in missing list (got: '$result')"; FAIL=$((FAIL + 1))
fi

# ── Test 2: Missing 'commands' only (skills present) → commands reported ──────
echo ""
echo "Test 2: plugin.json has 'skills' but missing 'commands'"
cat > "$TMPROOT/plugin-no-commands.json" << 'EOF'
{
  "name": "brana",
  "version": "1.0.0",
  "skills": "./skills/"
}
EOF
result=$(check35_missing_fields "$TMPROOT/plugin-no-commands.json")
assert_nonempty "missing commands → detected" "$result"
if [[ "$result" == *"commands"* ]]; then
    TOTAL=$((TOTAL + 1)); echo "  PASS: 'commands' in missing list"; PASS=$((PASS + 1))
else
    TOTAL=$((TOTAL + 1)); echo "  FAIL: 'commands' not in missing list (got: '$result')"; FAIL=$((FAIL + 1))
fi
if [[ "$result" != *"skills"* ]]; then
    TOTAL=$((TOTAL + 1)); echo "  PASS: 'skills' not falsely flagged"; PASS=$((PASS + 1))
else
    TOTAL=$((TOTAL + 1)); echo "  FAIL: 'skills' falsely flagged (got: '$result')"; FAIL=$((FAIL + 1))
fi

# ── Test 3: Both fields present → no missing fields ───────────────────────────
echo ""
echo "Test 3: plugin.json has both 'skills' and 'commands'"
cat > "$TMPROOT/plugin-complete.json" << 'EOF'
{
  "name": "brana",
  "version": "1.0.0",
  "skills": "./skills/",
  "commands": ["./commands/repo-cleanup.md"]
}
EOF
result=$(check35_missing_fields "$TMPROOT/plugin-complete.json")
assert_empty "both fields present → no violations" "$result"

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
