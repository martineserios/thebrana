#!/usr/bin/env bash
# t-2835 (ADR-084 §4 code-review VENDOR+WRAP): the two-axis-review adapter's
# Spec sub-agent needs a spec brief built from a brana task's own fields
# (`acceptance_criteria` / `context`'s `AC:` lines) -- never from
# docs/agents/issue-tracker.md (that file is the tracker *verb* map, not a
# spec source; AC2 of t-2835 is explicit that this is a different concern).
# This test pins the lookup's precedence and its missing-spec exit contract:
# no spec found must be a distinct, explicit signal ("no spec available"),
# never a hard failure and never a fabricated spec.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LOOKUP_SCRIPT="$REPO_ROOT/system/scripts/two-axis-spec-lookup.sh"
PASS=0
FAIL=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

FIXTURES=$(mktemp -d)
trap 'rm -rf "$FIXTURES"' EXIT

echo "== two-axis-spec-lookup.sh: acceptance_criteria present -> used verbatim, exit 0 =="
cat > "$FIXTURES/with-ac.json" <<'EOF'
{
  "id": "t-9001",
  "acceptance_criteria": ["all tests green", "no lint errors"],
  "context": "AC: this should not be used\nsome tactical note"
}
EOF
OUT=$("$LOOKUP_SCRIPT" "$FIXTURES/with-ac.json")
RC=$?
check "exit code 0 when acceptance_criteria present" "0" "$RC"
check "output includes first AC item" "yes" "$(printf '%s' "$OUT" | grep -qF 'all tests green' && echo yes || echo no)"
check "output includes second AC item" "yes" "$(printf '%s' "$OUT" | grep -qF 'no lint errors' && echo yes || echo no)"
check "output does NOT fall back to context AC: lines when acceptance_criteria is non-empty" "no" "$(printf '%s' "$OUT" | grep -qF 'this should not be used' && echo yes || echo no)"

echo ""
echo "== two-axis-spec-lookup.sh: empty acceptance_criteria, AC: lines in context -> fallback, exit 0 =="
cat > "$FIXTURES/context-ac-only.json" <<'EOF'
{
  "id": "t-9002",
  "acceptance_criteria": [],
  "context": "some note\nAC: branch merged to main\nAC: tasks.json updated\nanother note"
}
EOF
OUT=$("$LOOKUP_SCRIPT" "$FIXTURES/context-ac-only.json")
RC=$?
check "exit code 0 when context has AC: lines" "0" "$RC"
check "output includes first context AC: line" "yes" "$(printf '%s' "$OUT" | grep -qF 'branch merged to main' && echo yes || echo no)"
check "output includes second context AC: line" "yes" "$(printf '%s' "$OUT" | grep -qF 'tasks.json updated' && echo yes || echo no)"
check "output excludes non-AC: context lines" "no" "$(printf '%s' "$OUT" | grep -qF 'some note' && echo yes || echo no)"

echo ""
echo "== two-axis-spec-lookup.sh: no acceptance_criteria, no AC: lines -> explicit 'no spec available', exit 2 =="
cat > "$FIXTURES/no-spec.json" <<'EOF'
{
  "id": "t-9003",
  "acceptance_criteria": [],
  "context": "just a tactical note, nothing AC-shaped"
}
EOF
OUT=$("$LOOKUP_SCRIPT" "$FIXTURES/no-spec.json")
RC=$?
check "exit code 2 (skip signal, not failure) when no spec found" "2" "$RC"
check "stdout is the literal skip message" "no spec available" "$OUT"

echo ""
echo "== two-axis-spec-lookup.sh: missing/absent fields -> treated as no spec, not a crash =="
cat > "$FIXTURES/missing-fields.json" <<'EOF'
{ "id": "t-9004" }
EOF
"$LOOKUP_SCRIPT" "$FIXTURES/missing-fields.json" >/tmp/two-axis-missing-fields.out 2>&1
RC=$?
check "exit code 2 when fields absent entirely (no crash)" "2" "$RC"
check "stdout is the literal skip message on absent fields" "no spec available" "$(cat /tmp/two-axis-missing-fields.out)"
rm -f /tmp/two-axis-missing-fields.out

echo ""
echo "== two-axis-spec-lookup.sh: nonexistent input file -> hard failure, distinct from no-spec =="
"$LOOKUP_SCRIPT" "$FIXTURES/does-not-exist.json" >/dev/null 2>&1
RC=$?
check "exit code 1 (hard error) for a missing input file, not 2 (skip)" "1" "$RC"

echo ""
echo "== Results: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
