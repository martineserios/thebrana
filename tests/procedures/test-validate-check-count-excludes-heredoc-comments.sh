#!/usr/bin/env bash
# Regression test: ACTUAL_CHECKS (validate.sh's own self-reported check count)
# is computed as `grep -c "^# Check [0-9]" validate.sh` against the WHOLE
# file — including heredoc bodies. Two Python comments embedded in Check 18's
# graph-integrity heredoc ("# Check 1: ...", "# Check 2: ...") happened to
# match that pattern — they are internal sub-check labels for a Python
# script, not top-level validate.sh checks — and inflated the reported total
# by 2 (t-3168, found by the challenger gate reviewing the sibling Check
# 27/25 collision fix; renamed to "Sub-check A"/"Sub-check B").
#
# Scoped narrowly to the ONE heredoc that actually caused this (delimited by
# its own `<<'PYEOF' ... PYEOF` markers) rather than a repo-wide heuristic —
# a generic "every # Check N header needs a matching pass/fail/warn call
# site" rule does not hold across validate.sh's ~2800 lines (many legitimate
# checks use other messaging conventions) and produced 21 false positives
# when tried.
#
# Run: bash tests/procedures/test-validate-check-count-excludes-heredoc-comments.sh

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

echo "=== test-validate-check-count-excludes-heredoc-comments.sh ==="
echo ""

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATE_SH="$REPO_ROOT/validate.sh"

if [ ! -f "$VALIDATE_SH" ]; then
    echo "ERROR: $VALIDATE_SH not found"
    exit 1
fi

# Locate Check 18's Python heredoc precisely: the first `<<'PYEOF'` after the
# "# Check 18: Graph integrity" header, through its matching `PYEOF` close.
CHECK18_LINE=$(grep -n '^# Check 18: Graph integrity' "$VALIDATE_SH" | head -1 | cut -d: -f1)
if [ -z "$CHECK18_LINE" ]; then
    echo "ERROR: '# Check 18: Graph integrity' header not found in $VALIDATE_SH"
    exit 1
fi
HEREDOC_START=$(tail -n "+${CHECK18_LINE}" "$VALIDATE_SH" | grep -n "<<'PYEOF'" | head -1 | cut -d: -f1)
if [ -z "$HEREDOC_START" ]; then
    echo "ERROR: no <<'PYEOF' heredoc found after the Check 18 header"
    exit 1
fi
HEREDOC_START=$((CHECK18_LINE + HEREDOC_START - 1))
HEREDOC_END=$(tail -n "+${HEREDOC_START}" "$VALIDATE_SH" | grep -n '^PYEOF$' | head -1 | cut -d: -f1)
if [ -z "$HEREDOC_END" ]; then
    echo "ERROR: no closing PYEOF found for the Check 18 heredoc"
    exit 1
fi
HEREDOC_END=$((HEREDOC_START + HEREDOC_END - 1))

echo "Check 18 heredoc spans lines $HEREDOC_START-$HEREDOC_END"
BODY=$(sed -n "${HEREDOC_START},${HEREDOC_END}p" "$VALIDATE_SH")

POLLUTERS=$(printf '%s\n' "$BODY" | grep -c '^# Check [0-9]' || true)
assert_true "no line inside Check 18's Python heredoc matches the '# Check N' header pattern (found $POLLUTERS)" \
    '[ "$POLLUTERS" -eq 0 ]'

echo ""
echo "=== $PASS/$TOTAL passed ==="
[ "$FAIL" -eq 0 ]
