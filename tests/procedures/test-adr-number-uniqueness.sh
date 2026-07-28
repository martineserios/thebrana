#!/usr/bin/env bash
# test-adr-number-uniqueness.sh — t-2515.
#
# Guards system/scripts/check-adr-uniqueness.sh, the backstop that would have
# caught the five colliding ADR numbers cleared on 2026-07-28 (002/026/048/062
# had sat duplicated on dev for months; 068 was assigned twice on the same day
# because the number was picked by listing the directory on a branch that could
# not see dev's newer ADR).
#
# The point of these tests is that the check FAILS on a duplicate. A guard that
# cannot fail is worse than none — it reports "clean" forever.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK="$SCRIPT_DIR/system/scripts/check-adr-uniqueness.sh"

PASSED=0
FAILED=0

ok()   { PASSED=$((PASSED + 1)); echo "  ok   — $1"; }
bad()  { FAILED=$((FAILED + 1)); echo "  FAIL — $1"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

echo "ADR number uniqueness check (t-2515)"

if [ ! -f "$CHECK" ]; then
    echo "  FAIL — $CHECK not found"
    exit 1
fi

# ── 1. unique set passes ────────────────────────────────────────────
mkdir -p "$TMP/unique"
touch "$TMP/unique/ADR-001-alpha.md" \
      "$TMP/unique/ADR-002-beta.md" \
      "$TMP/unique/ADR-070-gamma.md"
if bash "$CHECK" "$TMP/unique" >/dev/null 2>&1; then
    ok "a directory with no repeated numbers exits 0"
else
    bad "a unique directory must exit 0"
fi

# ── 2. duplicate is CAUGHT (the load-bearing case) ──────────────────
mkdir -p "$TMP/dupe"
touch "$TMP/dupe/ADR-001-alpha.md" \
      "$TMP/dupe/ADR-062-runner-executor-sandbox.md" \
      "$TMP/dupe/ADR-062-step-state-contract.md"
if bash "$CHECK" "$TMP/dupe" >/dev/null 2>&1; then
    bad "a duplicated number MUST exit non-zero — the guard cannot fail"
else
    ok "a duplicated number exits non-zero"
fi

# ── 3. the failure names the offending number ───────────────────────
# Without this the operator gets "duplicates found" and has to hunt.
DUPE_OUT=$(bash "$CHECK" "$TMP/dupe" 2>&1 || true)
if echo "$DUPE_OUT" | grep -q "ADR-062"; then
    ok "failure output names the duplicated number"
else
    bad "failure output must name the number; got: $DUPE_OUT"
fi

# ── 4. both colliding filenames are named ───────────────────────────
if echo "$DUPE_OUT" | grep -q "runner-executor-sandbox" \
   && echo "$DUPE_OUT" | grep -q "step-state-contract"; then
    ok "failure output names both colliding files"
else
    bad "failure output must name both files; got: $DUPE_OUT"
fi

# ── 5. three-way collision counts as one reported number ────────────
mkdir -p "$TMP/triple"
touch "$TMP/triple/ADR-009-a.md" "$TMP/triple/ADR-009-b.md" "$TMP/triple/ADR-009-c.md"
if bash "$CHECK" "$TMP/triple" >/dev/null 2>&1; then
    bad "a three-way collision must exit non-zero"
else
    ok "a three-way collision exits non-zero"
fi

# ── 6. boundary: empty directory is not a failure ───────────────────
# A fresh repo with no ADRs yet must not fail the build.
mkdir -p "$TMP/empty"
if bash "$CHECK" "$TMP/empty" >/dev/null 2>&1; then
    ok "an empty directory exits 0 (no ADRs is not a collision)"
else
    bad "an empty directory must not fail"
fi

# ── 7. boundary: non-ADR files are ignored ──────────────────────────
mkdir -p "$TMP/mixed"
touch "$TMP/mixed/ADR-001-alpha.md" "$TMP/mixed/README.md" "$TMP/mixed/template.md"
if bash "$CHECK" "$TMP/mixed" >/dev/null 2>&1; then
    ok "non-ADR files are ignored"
else
    bad "non-ADR files must not trip the check"
fi

# ── 8. boundary: missing directory reports, does not crash ──────────
if bash "$CHECK" "$TMP/does-not-exist" >/dev/null 2>&1; then
    bad "a missing directory must exit non-zero, not silently pass"
else
    ok "a missing directory exits non-zero rather than passing vacuously"
fi

# ── 9. the real repo is clean (regression guard) ────────────────────
if bash "$CHECK" "$SCRIPT_DIR/docs/architecture/decisions" >/dev/null 2>&1; then
    ok "the live decisions directory has no duplicate numbers"
else
    bad "the live decisions directory has duplicates — $(bash "$CHECK" "$SCRIPT_DIR/docs/architecture/decisions" 2>&1 | head -3)"
fi

echo ""
echo "  $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
