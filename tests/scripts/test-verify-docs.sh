#!/usr/bin/env bash
# Test for verify-docs.sh
# Spec: system/scripts/verify-docs.spec.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERIFY="$REPO_ROOT/system/scripts/verify-docs.sh"

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected output to contain '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== test-verify-docs.sh ==="

# 1. Script exists and is executable
echo "Test: script exists and is executable"
assert_eq "script exists" "true" "$([[ -f "$VERIFY" ]] && echo true || echo false)"
assert_eq "script is executable" "true" "$([[ -x "$VERIFY" ]] && echo true || echo false)"

# 2. Default invocation exits 0 or 1 (never 2)
echo "Test: default invocation exit code"
ec=0; "$VERIFY" >/dev/null 2>&1 || ec=$?
assert_eq "exit 0 or 1" "true" "$( [[ $ec -eq 0 || $ec -eq 1 ]] && echo true || echo false )"

# 3. Default output contains expected sections
echo "Test: default output sections"
OUTPUT=$("$VERIFY" 2>&1) || true
assert_contains "Structural section" "Structural" "$OUTPUT"
assert_contains "Sample section" "Sample of" "$OUTPUT"

# 4. --sample 3 produces exactly 3 sample entries
echo "Test: --sample N respects N"
SAMPLE_OUT=$("$VERIFY" --sample 3 2>&1) || true
SAMPLE_COUNT=$(echo "$SAMPLE_OUT" | grep -cE '^\s*\[[0-9]+\]\s' || true)
assert_eq "3 sample entries" "3" "$SAMPLE_COUNT"

# 5. --json emits valid JSON
echo "Test: --json emits valid JSON"
JSON_OUT=$("$VERIFY" --json --sample 2 2>&1) || true
echo "$JSON_OUT" | jq . >/dev/null 2>&1
JQ_EC=$?
assert_eq "jq parses output" "0" "$JQ_EC"
# JSON should have structural and sample keys
assert_contains "JSON has structural key" '"structural"' "$JSON_OUT"
assert_contains "JSON has sample key" '"sample"' "$JSON_OUT"

# 6. --seed reproducibility
echo "Test: --seed reproducibility"
RUN1=$("$VERIFY" --json --sample 5 --seed 42 2>&1 | jq -c '.sample | map(.doc)' 2>/dev/null) || RUN1="err"
RUN2=$("$VERIFY" --json --sample 5 --seed 42 2>&1 | jq -c '.sample | map(.doc)' 2>/dev/null) || RUN2="err"
assert_eq "same seed → same sample order" "$RUN1" "$RUN2"

# 7. Exit 2 if validate.sh is missing — simulate by overriding path
echo "Test: exit 2 if validate.sh missing"
WORK=$(mktemp -d)
mkdir -p "$WORK/system/scripts" "$WORK/docs"
cp "$VERIFY" "$WORK/system/scripts/verify-docs.sh"
chmod +x "$WORK/system/scripts/verify-docs.sh"
ec=0
BRANA_REPO_ROOT="$WORK" "$WORK/system/scripts/verify-docs.sh" >/dev/null 2>&1 || ec=$?
assert_eq "exit 2 on missing validate" "2" "$ec"
rm -rf "$WORK"

# Summary
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
