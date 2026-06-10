#!/usr/bin/env bash
# Tests for ruflo-cli.sh — the single sanctioned ruflo CLI entry (t-1936).
#
# Two diseases this wrapper cures:
#   1. The npm tarball ships bin/ruflo.js with a CRLF shebang (t-1934) — direct
#      invocation dies with "env: 'node\r'". The wrapper execs node + resolved .js.
#   2. Session rows score a constant 0.5; namespace-less `memory search` returns
#      them as noise unless threshold >= 0.55. Callers shouldn't need to know the
#      rule — the wrapper injects it (architecture review 2026-06-10 §4, t-1936).
#
# Tests:
#   T1: wrapper exists and is executable
#   T2: namespace-less `memory search` gets --threshold 0.55 injected (DRYRUN)
#   T3: --namespace query is NOT modified (DRYRUN)
#   T4: explicit --threshold is respected, no double-inject (DRYRUN)
#   T5: resolved command is node + *.js, never the shebang bin (DRYRUN)
#   T6: non-search subcommands pass through unmodified (DRYRUN)
#   T7: both cf-env.sh variants route $CF through the wrapper
#   T8: session-start.sh recall is namespace-scoped (no naked memory search)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WRAPPER="$REPO_ROOT/system/scripts/ruflo-cli.sh"

PASS=0; FAIL=0; TOTAL=0

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL+1))
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS+1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $desc — '$needle' not in: $haystack"
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL+1))
    if [[ "$haystack" == *"$needle"* ]]; then
        FAIL=$((FAIL+1)); echo "  FAIL: $desc — '$needle' unexpectedly in: $haystack"
    else
        PASS=$((PASS+1)); echo "  PASS: $desc"
    fi
}

echo "=== ruflo-cli.sh wrapper (t-1936) ==="

# T1
TOTAL=$((TOTAL+1))
if [ -x "$WRAPPER" ]; then
    PASS=$((PASS+1)); echo "  PASS: T1: wrapper exists and is executable"
else
    FAIL=$((FAIL+1)); echo "  FAIL: T1: $WRAPPER missing or not executable"
    echo ""; echo "$PASS/$TOTAL passed"; exit 1
fi

# T2 — namespace-less search gets the contamination guard
OUT=$(RUFLO_CLI_DRYRUN=1 bash "$WRAPPER" memory search --query "client:thebrana" --format json 2>&1)
assert_contains "T2: namespace-less search injects --threshold 0.55" "--threshold 0.55" "$OUT"

# T3 — namespaced search untouched
OUT=$(RUFLO_CLI_DRYRUN=1 bash "$WRAPPER" memory search --query "x" --namespace pattern 2>&1)
assert_not_contains "T3: namespaced search not modified" "--threshold 0.55" "$OUT"

# T4 — explicit threshold respected
OUT=$(RUFLO_CLI_DRYRUN=1 bash "$WRAPPER" memory search --query "x" --threshold 0.4 2>&1)
assert_not_contains "T4: explicit threshold not double-injected" "0.55" "$OUT"
assert_contains "T4b: explicit threshold preserved" "--threshold 0.4" "$OUT"

# T5 — node + .js resolution, never the shebang bin
OUT=$(RUFLO_CLI_DRYRUN=1 bash "$WRAPPER" memory stats 2>&1)
assert_contains "T5: resolves to a .js entry via node" ".js" "$OUT"
assert_not_contains "T5b: never execs bin/ruflo directly" "bin/ruflo " "$OUT"

# T6 — non-search subcommands pass through
OUT=$(RUFLO_CLI_DRYRUN=1 bash "$WRAPPER" memory store -k "a" -v "b" 2>&1)
assert_not_contains "T6: store passes through unmodified" "--threshold" "$OUT"

# T7 — cf-env variants route through the wrapper
for cfenv in system/scripts/cf-env.sh system/hooks/lib/cf-env.sh; do
    HIT=$(grep -c "ruflo-cli.sh" "$REPO_ROOT/$cfenv" || true)
    TOTAL=$((TOTAL+1))
    if [ "${HIT:-0}" -gt 0 ]; then
        PASS=$((PASS+1)); echo "  PASS: T7: $cfenv routes CF through wrapper"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: T7: $cfenv does not reference ruflo-cli.sh"
    fi
done

# T8 — session-start recall is namespace-scoped
RECALL_LINE=$(grep '\$CF memory search' "$REPO_ROOT/system/hooks/session-start.sh" | head -1)
assert_contains "T8: session-start recall uses --namespace" "--namespace" "$RECALL_LINE"

echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
