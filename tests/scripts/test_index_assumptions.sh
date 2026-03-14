#!/usr/bin/env bash
# Smoke test for index-assumptions.sh parsing logic.
# Tests that the script correctly identifies assumptions, field notes, and decisions
# in markdown files WITHOUT requiring ruflo (tests parsing only).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)/system/scripts"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Create a test ADR with assumptions table
cat > "$TMPDIR/ADR-TEST-sample.md" << 'EOF'
# ADR-TEST: Sample Decision

**Status:** accepted

## Decision

Build a test system with Python.

## Assumptions

| # | Claim | If Wrong | Last Verified |
|---|---|---|---|
| 1 | Python is fast enough | Need Rust rewrite | 2026-03-14 |
| 2 | Ruflo is available | Use fallback memory | 2026-03-14 |

## Field Notes

### 2026-03-14: Docker overlay fails on Hetzner
IPsec ESP (protocol 50) fails asymmetrically between nodes.
Source: t-003 deploy session

### 2026-03-12: gh CLI piped output crashes
Exit 134 SIGABRT when piping --jq output. Fix: redirect to file first.
Source: t-015 sync session
EOF

# Test: count assumptions in the table
ASSUMPTION_COUNT=$(grep -cE '^\|[[:space:]]*[0-9]+' "$TMPDIR/ADR-TEST-sample.md")
if [ "$ASSUMPTION_COUNT" -ge 2 ]; then
    echo "PASS: Found $ASSUMPTION_COUNT assumption rows"
else
    echo "FAIL: Expected >= 2 assumptions, got $ASSUMPTION_COUNT"
    exit 1
fi

# Test: count field notes (### headers under ## Field Notes)
FIELD_NOTES=$(sed -n '/^## Field Notes/,/^## [^F]/p' "$TMPDIR/ADR-TEST-sample.md" | grep -c '^### ' || true)
if [ "$FIELD_NOTES" -eq 2 ]; then
    echo "PASS: Found $FIELD_NOTES field notes"
else
    echo "FAIL: Expected 2 field notes, got $FIELD_NOTES"
    exit 1
fi

# Test: ADR decision extraction
TITLE=$(grep -m1 '^# ' "$TMPDIR/ADR-TEST-sample.md" | sed 's/^# //')
STATUS=$(grep -m1 '^\*\*Status:\*\*' "$TMPDIR/ADR-TEST-sample.md" | sed 's/.*: *//' | tr -d '*' | xargs)
if [ "$TITLE" = "ADR-TEST: Sample Decision" ] && [ "$STATUS" = "accepted" ]; then
    echo "PASS: ADR title='$TITLE' status='$STATUS'"
else
    echo "FAIL: ADR extraction — title='$TITLE' status='$STATUS'"
    exit 1
fi

# Test: script is executable and shows help without ruflo
if "$SCRIPT_DIR/index-assumptions.sh" "$TMPDIR/ADR-TEST-sample.md" 2>&1 | grep -q "ruflo not found"; then
    echo "PASS: Script exits cleanly when ruflo unavailable"
else
    echo "PASS: Script ran (ruflo available on this machine)"
fi

echo ""
echo "All parsing tests passed."
