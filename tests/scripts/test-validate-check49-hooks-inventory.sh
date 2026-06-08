#!/usr/bin/env bash
# Unit test for Check 49: every system/hooks/*.sh must appear in hooks.md inventory.
#
# Tests:
#   T1 — script present in hooks.md inventory → no warning
#   T2 — script missing from hooks.md inventory → warning emitted
#   T3 — lib/ subdir scripts excluded from check
#   T4 — deregistered (strikethrough ~~) scripts count as mentioned

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_empty() {
    local desc="$1" result="$2"
    TOTAL=$((TOTAL + 1))
    if [ -z "$result" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected no violations, got: $result"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" result="$2" needle="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$result" | grep -qF "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected '$needle' in output, got: $result"
        FAIL=$((FAIL + 1))
    fi
}

# Extract Check 49 logic — inline reproduction of the validate.sh implementation.
# Given a list of hook scripts (one per line) and hooks.md content, returns missing entries.
check49_missing() {
    local hook_scripts="$1"   # newline-separated basenames
    local hooks_md="$2"       # full content of hooks.md

    # Extract all script names mentioned in the inventory table
    # Matches both normal: | `foo.sh` | and strikethrough: | ~~`foo.sh`~~ |
    # sed extracts first-column backtick script only (greedy match would pick last)
    INVENTORY=$(echo "$hooks_md" \
        | awk '/^## Hook inventory/{f=1; next} f && /^## /{exit} f' \
        | grep -E '^\| (~~)?`[a-zA-Z0-9_.-]+\.sh`' \
        | sed 's/^[^`]*`\([^`]*\.sh\)`.*/\1/' \
        | sort -u)

    while IFS= read -r script; do
        [ -z "$script" ] && continue
        if ! echo "$INVENTORY" | grep -qxF "$script"; then
            echo "$script"
        fi
    done <<< "$hook_scripts"
}

# ── T1: script present in inventory → no warning ─────────────────────────────
echo "=== T1: script present in hooks.md inventory ==="

HOOKS_MD_T1="## Hook inventory
| Script | Event | Matcher | Description |
|--------|-------|---------|-------------|
| \`my-hook.sh\` | PreToolUse | \`Write\` | Does something |
"

result=$(check49_missing "my-hook.sh" "$HOOKS_MD_T1")
assert_empty "T1: present script produces no warning" "$result"

# ── T2: script missing from inventory → warning ───────────────────────────────
echo "=== T2: script missing from hooks.md inventory ==="

result=$(check49_missing "brand-new-hook.sh" "$HOOKS_MD_T1")
assert_contains "T2: missing script produces warning" "$result" "brand-new-hook.sh"

# ── T3: lib/ scripts excluded (only basenames of top-level *.sh passed) ───────
# The check scans only system/hooks/*.sh (maxdepth 1), so lib/ scripts never appear.
# Simulate by NOT including lib scripts in the input list.
echo "=== T3: lib/ exclusion ==="

result=$(check49_missing "my-hook.sh" "$HOOKS_MD_T1")
assert_empty "T3: no lib/ scripts in input → no spurious warnings" "$result"

# ── T4: strikethrough (deregistered) scripts count as mentioned ───────────────
echo "=== T4: deregistered (~~) scripts count as mentioned ==="

HOOKS_MD_T4="## Hook inventory
| Script | Event | Matcher | Description |
|--------|-------|---------|-------------|
| ~~\`old-hook.sh\`~~ | ~~PreToolUse~~ | ~~\`Write\`~~ | **Deregistered** |
"

result=$(check49_missing "old-hook.sh" "$HOOKS_MD_T4")
assert_empty "T4: deregistered script counts as mentioned" "$result"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Check 49 test summary: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
