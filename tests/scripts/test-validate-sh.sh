#!/usr/bin/env bash
# Regression harness for validate.sh false-positive fixes introduced in ec2edad.
#
# Tests three specific regressions (each would have produced false FAILs before ec2edad):
#   T1 — Check 9: multi-token hooks.json command ("bash ${CLAUDE_PLUGIN_ROOT}/x.sh")
#        word-splits into ["bash", "path"] if iterated with for-loop.
#   T2 — Check 28: test script using python3 in hooks/tests/ should be excluded
#        (requires --exclude-dir=tests).
#   T3 — Check 6b: .md file with a long alphanumeric ID (Google Sheets / Drive IDs)
#        should be excluded (requires --exclude="*.md").
#
# Each test extracts the relevant check logic inline (no full validate.sh run).

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

assert_empty() {
    local desc="$1" result="$2"
    TOTAL=$((TOTAL + 1))
    if [ -z "$result" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected no violations, got:"
        echo "$result" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
}

# ── T1: Check 9 — multi-token hooks.json command (bash + path) ───────────────
# The pre-ec2edad code used `for cmd in $HJ_CMDS` which word-splits
# "bash ${CLAUDE_PLUGIN_ROOT}/hooks/x.sh" into ["bash", "path"].
# Fix: while IFS= read -r cmd; ... done <<< "$(jq ...)"
# Verification: the script path should be the LAST token (awk '{print $NF}').

echo "=== T1: Check 9 — multi-token hooks.json command ==="

# Reproduce the fixed extraction logic from Check 9
check9_extract_script_path() {
    local cmd="$1"
    echo "$cmd" | awk '{print $NF}'
}

multi_token_cmd='bash ${CLAUDE_PLUGIN_ROOT}/hooks/my-hook.sh'
extracted=$(check9_extract_script_path "$multi_token_cmd")

# The extracted path should be "${CLAUDE_PLUGIN_ROOT}/hooks/my-hook.sh"
# not "bash" (which would happen with word-splitting)
if [[ "$extracted" == *"my-hook.sh"* ]]; then
    echo "  PASS: T1a — awk NF extracts script path from multi-token command"
    PASS=$((PASS + 1))
else
    echo "  FAIL: T1a — awk NF returned '$extracted' (expected path ending in my-hook.sh)"
    FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

# Verify PLUGIN_ROOT check runs against the script path, not "bash"
script_path=$(check9_extract_script_path "$multi_token_cmd")
if echo "$script_path" | grep -q '\${CLAUDE_PLUGIN_ROOT}'; then
    echo "  PASS: T1b — PLUGIN_ROOT check targets script path (not 'bash')"
    PASS=$((PASS + 1))
else
    echo "  FAIL: T1b — PLUGIN_ROOT check would miss path '$script_path'"
    FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

# Verify resolution works: ${CLAUDE_PLUGIN_ROOT}/hooks/x.sh → SYSTEM_DIR/hooks/x.sh
FAKE_SYSTEM="$TMPROOT/system"
mkdir -p "$FAKE_SYSTEM/hooks"
touch "$FAKE_SYSTEM/hooks/my-hook.sh"
chmod +x "$FAKE_SYSTEM/hooks/my-hook.sh"
resolved=$(echo "$script_path" | sed "s|\${CLAUDE_PLUGIN_ROOT}|$FAKE_SYSTEM|g")
if [ -f "$resolved" ]; then
    echo "  PASS: T1c — resolved path '$resolved' exists"
    PASS=$((PASS + 1))
else
    echo "  FAIL: T1c — resolved path '$resolved' does not exist"
    FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

echo ""

# ── T2: Check 28 — python3 in hooks/tests/ must be excluded ──────────────────
# Pre-ec2edad: grep lacked --exclude-dir=tests, so test scripts using python3
# to build fixture JSON would trigger "bare python3 in system/hooks/" false FAIL.

echo "=== T2: Check 28 — python3 in hooks/tests/ excluded ==="

mkdir -p "$TMPROOT/hooks2/tests"

# A legitimate test helper that uses python3 to build input fixtures
cat > "$TMPROOT/hooks2/tests/test-my-hook.sh" << 'INNER'
#!/usr/bin/env bash
# Test uses python3 to build JSON fixture
INPUT=$(python3 -c 'import json; print(json.dumps({"tool_name":"Write"}))')
INNER

# A clean hook (no python3)
cat > "$TMPROOT/hooks2/clean-hook.sh" << 'INNER'
#!/usr/bin/env bash
cd /tmp 2>/dev/null || true
INPUT=$(cat)
echo '{"continue": true}'
INNER

# Check 28 logic: grep with --exclude-dir=tests (fixed version)
check28_with_exclusion() {
    local hooks_dir="$1"
    grep -rn "python3" "$hooks_dir" --include="*.sh" \
        --exclude-dir=tests 2>/dev/null \
        | grep -v "uv run python3" \
        | grep -v ":[[:space:]]*#" \
        || true
}

# Without exclusion (old buggy behavior)
check28_without_exclusion() {
    local hooks_dir="$1"
    grep -rn "python3" "$hooks_dir" --include="*.sh" 2>/dev/null \
        | grep -v "uv run python3" \
        | grep -v ":[[:space:]]*#" \
        || true
}

result_fixed=$(check28_with_exclusion "$TMPROOT/hooks2")
assert_empty "T2a — with --exclude-dir=tests: tests/test-my-hook.sh not flagged" "$result_fixed"

result_old=$(check28_without_exclusion "$TMPROOT/hooks2")
TOTAL=$((TOTAL + 1))
if [ -n "$result_old" ]; then
    echo "  PASS: T2b — without exclusion: confirms false-positive would occur (regression reproduced)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: T2b — expected to detect python3 in test file but found nothing"
    FAIL=$((FAIL + 1))
fi

echo ""

# ── T3: Check 6b — .md file with long alphanumeric ID excluded ───────────────
# Pre-ec2edad: grep over state/ lacked --exclude="*.md", so .md files
# containing Google Sheets IDs (44-char alphanumeric) would trigger
# "key-shaped value in state/" false FAIL.

echo "=== T3: Check 6b — .md file with long ID excluded ==="

mkdir -p "$TMPROOT/state"

# A portfolio.md with a Google Sheets ID (typical 44-char alphanumeric)
cat > "$TMPROOT/state/portfolio.md" << 'INNER'
# Portfolio

| Sheet | ID |
|-------|-----|
| Metrics | 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms |
INNER

# Check 6b logic: grep with --exclude="*.md" (fixed version)
check6b_with_exclusion() {
    local state_dir="$1"
    grep -rn --exclude="patterns-export.json" --exclude="*.md" \
        -E '[A-Za-z0-9]{40,}' "$state_dir" 2>/dev/null \
        | grep -v ":[[:space:]]*#" \
        || true
}

# Without exclusion (old buggy behavior)
check6b_without_exclusion() {
    local state_dir="$1"
    grep -rn --exclude="patterns-export.json" \
        -E '[A-Za-z0-9]{40,}' "$state_dir" 2>/dev/null \
        | grep -v ":[[:space:]]*#" \
        || true
}

result_fixed=$(check6b_with_exclusion "$TMPROOT/state")
assert_empty "T3a — with --exclude=*.md: portfolio.md ID not flagged" "$result_fixed"

result_old=$(check6b_without_exclusion "$TMPROOT/state")
TOTAL=$((TOTAL + 1))
if [ -n "$result_old" ]; then
    echo "  PASS: T3b — without exclusion: confirms false-positive would occur (regression reproduced)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: T3b — expected to detect long ID in .md but found nothing"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
