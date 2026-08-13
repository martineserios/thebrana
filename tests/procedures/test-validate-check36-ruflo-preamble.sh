#!/usr/bin/env bash
# Regression test: Check 36's ruflo-call detection must distinguish an actual
# call site (mcp__ruflo__toolname(...)) from a prose mention (backticked or
# plain-text reference to the tool name with no call syntax).
#
# Before this fix, Check 36 did `grep -q "mcp__ruflo__"` against the WHOLE
# file body — any mention of a ruflo tool name anywhere, including
# explanatory prose about why NOT to call it, was treated as a call site
# requiring a `<!-- ruflo preamble -->` block. build-loop.md:61 says
# "(`mcp__ruflo__agent_spawn` is bookkeeping-only under subscription...)" —
# pure prose, no invocation — and still failed the check (live 2026-08-12).
#
# This test extracts the detection line from validate.sh so it exercises the
# shipped source, not a copy (t-1978 rot class).
#
# Run: bash tests/procedures/test-validate-check36-ruflo-preamble.sh

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_true() {
    local desc="$1" cond="$2"
    TOTAL=$((TOTAL + 1))
    if eval "$cond"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

assert_false() {
    local desc="$1" cond="$2"
    TOTAL=$((TOTAL + 1))
    if eval "$cond"; then
        echo "  FAIL: $desc — expected no match"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    fi
}

echo "=== test-validate-check36-ruflo-preamble.sh ==="
echo ""

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATE_SH="$REPO_ROOT/validate.sh"

if [ ! -f "$VALIDATE_SH" ]; then
    echo "ERROR: $VALIDATE_SH not found"
    exit 1
fi

# Extract the detection regex verbatim from validate.sh's Check 36 block —
# this is the actual grep pattern used to decide "does this content contain
# an mcp__ruflo__ call site." The RUFLO-CALL-DETECT comment marks the block;
# the pattern itself lives on the `grep -qE "..."` line just below it.
if ! grep -q 'RUFLO-CALL-DETECT:' "$VALIDATE_SH"; then
    echo "ERROR: RUFLO-CALL-DETECT marker not found in $VALIDATE_SH"
    exit 1
fi
DETECT_LINE=$(grep -n 'grep -qE "mcp__ruflo__' "$VALIDATE_SH" | head -1 | cut -d: -f1)
if [ -z "$DETECT_LINE" ]; then
    echo "ERROR: could not find the grep -qE detection line in $VALIDATE_SH"
    exit 1
fi
DETECT_PATTERN=$(sed -n "${DETECT_LINE}p" "$VALIDATE_SH" | sed -E 's/^[^"]*"([^"]*)".*/\1/')
if [ -z "$DETECT_PATTERN" ]; then
    echo "ERROR: could not extract the grep pattern from the detection line"
    exit 1
fi
echo "Extracted pattern: $DETECT_PATTERN"
echo ""

# --- Case A: prose mention, no call syntax — must NOT match ---
PROSE='(`mcp__ruflo__agent_spawn` is bookkeeping-only under subscription, ADR-059)'
assert_false "prose mention of a tool name is not treated as a call site" \
    "grep -qE \"$DETECT_PATTERN\" <<< '$PROSE'"

# --- Case B: real call site with args — must match ---
REALCALL='mcp__ruflo__memory_search(query: "{query}", namespace: "knowledge", limit: 5, threshold: 0.3)'
assert_true "a real call site (name immediately followed by paren) is detected" \
    "grep -qE \"$DETECT_PATTERN\" <<< '$REALCALL'"

# --- Case C: real call site, no-arg form — must match ---
REALCALL_NOARG='mcp__ruflo__agentdb_health()'
assert_true "a real no-arg call site is detected" \
    "grep -qE \"$DETECT_PATTERN\" <<< '$REALCALL_NOARG'"

# --- Case D: bare mention in a comma list (ToolSearch select string) — should NOT match ---
SELECTLIST='ToolSearch("select:mcp__ruflo__memory_search,mcp__ruflo__claims_claim")'
assert_false "a bare name inside a ToolSearch select-list (no direct paren) is not a call site" \
    "grep -qE \"$DETECT_PATTERN\" <<< '$SELECTLIST'"

echo ""
echo "=== $PASS/$TOTAL passed ==="
[ "$FAIL" -eq 0 ]
