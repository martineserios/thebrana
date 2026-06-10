#!/usr/bin/env bash
# Tests for the agent memory contract (t-1935).
#
# CC subagent frontmatter `memory:` accepts a SCOPE STRING (user|project|local),
# not a boolean. `memory: true` is silently ignored by Claude Code — no memory
# injection, no auto-enabled Write/Edit, no directory. This was the root cause
# behind "agent memory never existed" (architecture review 2026-06-10 §4).
#
# Tests verify:
#   T1: no agent in system/agents/ declares a non-scope memory value (true/false/etc.)
#   T2: bootstrap.sh pre-creates ~/.claude/agent-memory/ (docs don't guarantee auto-creation)
#   T3: validate.sh Check 4 FAILS (loud, not WARN) on an agent with `memory: true`
#   T4: validate.sh Check 4 passes an agent with `memory: user`

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$REPO_ROOT/validate.sh"
CANARY="$REPO_ROOT/system/agents/test-1935-canary.md"

trap 'rm -f "$CANARY"' EXIT

PASS=0; FAIL=0; TOTAL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL+1))
    if [[ "$actual" == "$expected" ]]; then
        PASS=$((PASS+1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $desc — expected '$expected', got '$actual'"
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL+1))
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS+1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $desc — '$needle' not found in output"
    fi
}

echo "=== agent memory contract (t-1935) ==="

# T1 — no agent declares a non-scope memory value
BAD_AGENTS=$(grep -El '^memory:[[:space:]]*(true|false|yes|no|on|off)[[:space:]]*$' \
    "$REPO_ROOT"/system/agents/*.md 2>/dev/null || true)
assert_eq "T1: no agent declares boolean memory (must be user|project|local)" "" "$BAD_AGENTS"

# T2 — bootstrap pre-creates the user-scope agent-memory directory
BOOTSTRAP_HIT=$(grep -c 'agent-memory' "$REPO_ROOT/bootstrap.sh" || true)
TOTAL=$((TOTAL+1))
if [ "${BOOTSTRAP_HIT:-0}" -gt 0 ]; then
    PASS=$((PASS+1)); echo "  PASS: T2: bootstrap.sh creates ~/.claude/agent-memory/"
else
    FAIL=$((FAIL+1)); echo "  FAIL: T2: bootstrap.sh has no agent-memory creation step"
fi

# T3 — validator catches a boolean memory value, loudly
cat > "$CANARY" <<'EOF'
---
name: test-1935-canary
description: "Canary agent for t-1935 memory contract test. Not a real agent."
memory: true
---
# Canary
EOF
OUT=$(bash "$VALIDATE" --check 4 2>&1 || true)
assert_contains "T3: Check 4 FAILs on memory: true" "invalid memory scope" "$OUT"

# T4 — valid scope passes
cat > "$CANARY" <<'EOF'
---
name: test-1935-canary
description: "Canary agent for t-1935 memory contract test. Not a real agent."
memory: user
---
# Canary
EOF
OUT=$(bash "$VALIDATE" --check 4 2>&1 || true)
TOTAL=$((TOTAL+1))
if [[ "$OUT" == *"test-1935-canary"*"invalid memory scope"* ]]; then
    FAIL=$((FAIL+1)); echo "  FAIL: T4: memory: user incorrectly flagged"
else
    PASS=$((PASS+1)); echo "  PASS: T4: memory: user accepted"
fi

rm -f "$CANARY"

echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
