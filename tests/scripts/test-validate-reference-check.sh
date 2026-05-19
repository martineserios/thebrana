#!/usr/bin/env bash
# Tests for validate.sh Check 29: reference docs up to date (t-1429).
#
# Strategy: run validate.sh against the real repo (so all pre-29 checks pass)
# with a mock brana injected at front of PATH. Check 29 is the only check whose
# behavior we vary between scenarios.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0
TOTAL=0

FAKE_BIN=$(mktemp -d)
trap 'rm -rf "$FAKE_BIN"' EXIT

make_brana() {
    local exit_code="$1"
    cat > "$FAKE_BIN/brana" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "reference" ] && [ "\${2:-}" = "generate" ] && [ "\${3:-}" = "--check" ]; then
    [ "$exit_code" -eq 0 ] && echo "  all reference docs up to date"
    [ "$exit_code" -ne 0 ] && echo "  would update hooks.md"
    exit $exit_code
fi
# Pass through all other subcommands to the real brana
exec "\$(command -v brana 2>/dev/null || echo /nonexistent/brana)" "\$@"
EOF
    chmod +x "$FAKE_BIN/brana"
}

run_validate() {
    # Prepend FAKE_BIN so our mock brana shadows the real one
    PATH="$FAKE_BIN:$PATH" bash "$REPO_ROOT/validate.sh" 2>&1 || true
}

assert_contains() {
    local desc="$1" pattern="$2" out="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$out" == *"$pattern"* ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected pattern: '$pattern'"
        echo "$out" | grep -E "Check 29|reference doc" | sed 's/^/    /' || true
        FAIL=$((FAIL + 1))
    fi
}

echo "Validate Reference Check Tests (t-1429)"
echo "========================================"

# Scenario 1: brana --check exits 0 → Check 29 passes
make_brana 0
OUT=$(run_validate)
assert_contains "brana --check exits 0 → check 29 passes" \
    "reference docs up to date" "$OUT"

# Scenario 2: brana --check exits 1 → Check 29 fails with actionable message
make_brana 1
OUT=$(run_validate)
assert_contains "brana --check exits 1 → check 29 reports 'out of date'" \
    "out of date" "$OUT"

echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
