#!/usr/bin/env bash
# Regression test: the optional golden-path-drift block (behind --golden,
# validate.sh's "Optional: Golden-path drift" section) mislabeled itself
# "Check 27" — the same number already owned by the real, always-run Check 27
# (MCP wrapper exec pattern, line ~1505) — and one of its own three branches
# additionally typo'd to "Check 25" instead of matching its siblings. Both
# strings were pure copy-paste drift with no test catching either (t-3168).
#
# This test extracts the golden-path block verbatim (delimited by its own
# section header and closing `fi`) so it exercises the shipped source, not a
# copy (t-1978 rot class), and asserts:
#   1. every "Check N" label inside the block uses the SAME number
#   2. that number is not already claimed by a `# Check N` header comment
#      elsewhere in the file (the actual collision class this bug was)
#
# Run: bash tests/procedures/test-validate-golden-path-check-number.sh

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

echo "=== test-validate-golden-path-check-number.sh ==="
echo ""

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATE_SH="$REPO_ROOT/validate.sh"

if [ ! -f "$VALIDATE_SH" ]; then
    echo "ERROR: $VALIDATE_SH not found"
    exit 1
fi

# Extract the golden-path block: from its section header to the matching `fi`.
START_LINE=$(grep -n '^# ── Optional: Golden-path drift' "$VALIDATE_SH" | head -1 | cut -d: -f1)
if [ -z "$START_LINE" ]; then
    echo "ERROR: golden-path section header not found in $VALIDATE_SH"
    exit 1
fi
# The block is `if $RUN_GOLDEN; then ... fi` — a fixed, small span; 20 lines
# is comfortably more than the block has ever needed.
BLOCK=$(sed -n "${START_LINE},$((START_LINE + 20))p" "$VALIDATE_SH")
BLOCK=$(printf '%s\n' "$BLOCK" | sed -n '1,/^fi$/p')

echo "Extracted block ($(printf '%s\n' "$BLOCK" | wc -l) lines):"
printf '%s\n' "$BLOCK" | sed 's/^/    /'
echo ""

# --- 1. every "Check N" label inside the block agrees on N ---
# Only the operative echo/pass/warn string literals count as labels — plain
# `#`-comment lines (e.g. this fix's own explanation, which necessarily
# mentions the old wrong numbers) must not be scanned or the test trips on
# its own prose.
NUMBERS=$(printf '%s\n' "$BLOCK" | grep -E '^\s*(echo|pass|warn) "Check [0-9]' \
    | grep -oE 'Check [0-9]+' | grep -oE '[0-9]+' | sort -u)
NUMBER_COUNT=$(printf '%s\n' "$NUMBERS" | grep -c .)
assert_true "the golden-path block uses exactly one Check number in all its branches (found: $(printf '%s' "$NUMBERS" | tr '\n' ' '))" \
    '[ "$NUMBER_COUNT" -eq 1 ]'

# --- 2. that number is not already claimed by a `# Check N` header elsewhere ---
if [ "$NUMBER_COUNT" -eq 1 ]; then
    GOLDEN_NUM=$(printf '%s' "$NUMBERS" | head -1)
    OTHER_OWNERS=$(grep -n "^# Check ${GOLDEN_NUM}[^0-9]" "$VALIDATE_SH" || true)
    assert_true "Check $GOLDEN_NUM is not already owned by a different '# Check $GOLDEN_NUM' header block elsewhere in validate.sh" \
        '[ -z "$OTHER_OWNERS" ]'
else
    echo "  SKIP: number-collision check (block does not even agree with itself)"
fi

echo ""
echo "=== $PASS/$TOTAL passed ==="
[ "$FAIL" -eq 0 ]
