#!/usr/bin/env bash
# Tests for /brana:close weight-adaptive LIGHT/FULL classification (t-1655).
#
# Covers the three ambiguous cases from ADR-040 decision 7:
#   .sh changed → FULL (behavioral, high-stakes hook edit)
#   tasks.json only → LIGHT (state file, not behavioral config)
#   settings.json → FULL (behavioral config)
#
# Run: bash tests/procedures/test-close-weight-adaptive.sh

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

# ── Helpers ──────────────────────────────────────────────────────────────────

assert_mode() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected $expected, got $actual)"
        FAIL=$((FAIL + 1))
    fi
}

# Replicate the classification bash from close.md Step 1 verbatim.
# Takes CHANGED_FILES (newline-separated) and COMMIT_COUNT as env vars.
# Returns CLOSE_MODE via stdout.
classify() {
    local COMMIT_COUNT="${1:-1}"
    local CHANGED_FILES="$2"
    local ARGUMENTS="${3:-}"
    local CLOSE_MODE BEHAVIORAL_JSON

    BEHAVIORAL_JSON=$(echo "$CHANGED_FILES" | grep -E '^(system|\.claude)/.*\.json$' \
                     | grep -v '^\.claude/tasks\.json$' || true)

    if [[ "$ARGUMENTS" == *"--light"* ]]; then CLOSE_MODE="LIGHT"
    elif [[ "$ARGUMENTS" == *"--full"* ]]; then CLOSE_MODE="FULL"
    elif [[ "${COMMIT_COUNT:-0}" -ge 2 ]]; then CLOSE_MODE="FULL"
    elif echo "$CHANGED_FILES" | grep -qE '\.(rs|ts|tsx|js|jsx|py|sh|toml|yaml|yml)$'; then CLOSE_MODE="FULL"
    elif [[ -n "$BEHAVIORAL_JSON" ]]; then CLOSE_MODE="FULL"
    else CLOSE_MODE="LIGHT"
    fi

    echo "$CLOSE_MODE"
}

echo "=== test-close-weight-adaptive.sh ==="
echo ""

# ── Case 1: .sh edit → FULL ───────────────────────────────────────────────────

echo "Case 1: .sh changed → FULL"
MODE=$(classify 1 "system/hooks/pre-tool-use.sh")
assert_mode ".sh file → FULL" "FULL" "$MODE"

MODE=$(classify 1 "system/scripts/some-script.sh")
assert_mode "scripts/*.sh → FULL" "FULL" "$MODE"

# ── Case 2: tasks.json only → LIGHT ──────────────────────────────────────────

echo ""
echo "Case 2: tasks.json only → LIGHT"
MODE=$(classify 1 ".claude/tasks.json")
assert_mode "tasks.json only → LIGHT" "LIGHT" "$MODE"

# tasks.json + .md should still be LIGHT (no code, no behavioral json)
MODE=$(classify 1 ".claude/tasks.json
docs/some-note.md")
assert_mode "tasks.json + .md → LIGHT" "LIGHT" "$MODE"

# ── Case 3: settings.json → FULL ─────────────────────────────────────────────

echo ""
echo "Case 3: settings.json → FULL"
MODE=$(classify 1 ".claude/settings.json")
assert_mode ".claude/settings.json → FULL" "FULL" "$MODE"

MODE=$(classify 1 "system/plugin.json")
assert_mode "system/*.json → FULL" "FULL" "$MODE"

# tasks.json alongside settings.json: settings wins → FULL
MODE=$(classify 1 ".claude/tasks.json
.claude/settings.json")
assert_mode "tasks.json + settings.json → FULL" "FULL" "$MODE"

# ── Escape hatches ────────────────────────────────────────────────────────────

echo ""
echo "Escape hatches"
MODE=$(classify 1 "system/hooks/pre-tool-use.sh" "--light")
assert_mode "--light overrides .sh (→ LIGHT)" "LIGHT" "$MODE"

MODE=$(classify 1 ".claude/tasks.json" "--full")
assert_mode "--full overrides tasks.json (→ FULL)" "FULL" "$MODE"

# ── Commit count ──────────────────────────────────────────────────────────────

echo ""
echo "Commit count"
MODE=$(classify 2 "README.md")
assert_mode "2 commits + only .md → FULL" "FULL" "$MODE"

MODE=$(classify 1 "README.md")
assert_mode "1 commit + only .md → LIGHT" "LIGHT" "$MODE"

# ── Code extensions ───────────────────────────────────────────────────────────

echo ""
echo "Code extensions"
for ext in rs ts tsx js jsx py toml yaml yml; do
    MODE=$(classify 1 "src/file.$ext")
    assert_mode ".$ext → FULL" "FULL" "$MODE"
done

# .md is not a code extension
MODE=$(classify 1 "docs/note.md")
assert_mode ".md → LIGHT" "LIGHT" "$MODE"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

[ "$FAIL" -eq 0 ] || exit 1
