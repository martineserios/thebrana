#!/usr/bin/env bash
# Test for verify-counts.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERIFY="$REPO_ROOT/system/scripts/verify-counts.sh"

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

echo "=== test-verify-counts.sh ==="

# 1. Script exists and is executable
echo "Test: script exists and is executable"
assert_eq "script exists" "true" "$([[ -f "$VERIFY" ]] && echo true || echo false)"
assert_eq "script is executable" "true" "$([[ -x "$VERIFY" ]] && echo true || echo false)"

# 2. Script runs without error
echo "Test: script runs without error"
OUTPUT=$("$VERIFY" 2>&1) || true
assert_eq "exit code 0 or 1" "true" "$( ("$VERIFY" >/dev/null 2>&1; ec=$?; [[ $ec -eq 0 || $ec -eq 1 ]] && echo true || echo false) )"

# 3. Output contains expected categories
echo "Test: output contains expected categories"
assert_contains "mentions skills" "skills" "$OUTPUT"
assert_contains "mentions agents" "agents" "$OUTPUT"
assert_contains "mentions rules" "rules" "$OUTPUT"
assert_contains "mentions commands" "commands" "$OUTPUT"

# 4. Output contains PASS or MISMATCH per category
echo "Test: output contains result indicators"
# Each category should have either PASS or MISMATCH
for category in skills agents rules commands; do
  line=$(echo "$OUTPUT" | grep -i "$category" | head -1)
  has_result=$(echo "$line" | grep -cE '(PASS|MISMATCH)' || true)
  assert_eq "$category has PASS or MISMATCH" "1" "$has_result"
done

# 5. Output contains filesystem and documented counts
echo "Test: output contains count numbers"
# Should see numbers like "filesystem: NN" and "documented: NN"
assert_contains "filesystem count shown" "filesystem:" "$OUTPUT"
assert_contains "documented count shown" "documented:" "$OUTPUT"

# Summary
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
