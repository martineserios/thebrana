#!/usr/bin/env bash
# validate.sh Check 77a/77b wiring (t-3447; spec cockpit.md §Check 77a / 77b):
#   77a (static, mods-check.sh --static) ALWAYS runs — under --fast too, no `claude` needed;
#   77b (engine, mods-check.sh --engine) is skipped with a WARN under --fast, and FAILS
#   (never passes silently) when `claude` is absent otherwise. Also: the header convention
#   line exists, both ids are in the remedy registry, and check-selector maps mods/ files to 77.
# Run: bash tests/scripts/test-validate-check77.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/tests/lib/path-without.sh"
# This suite proves the WIRING of Check 77; the base-ref behaviour of 77a's version guard is
# test-mods-check.sh's job. The tests CI job has no origin/dev ref (only the validate job
# fetches it), so pin the base to HEAD here (CI run 37140367665, t-3427).
export MODS_BASE_REF=HEAD
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }
cd "$ROOT" || exit 2
echo "=== test-validate-check77.sh ==="

echo "--- static surface"
assert "header convention: static assertions never sit behind --fast or an optional binary" yes "$(has 'never live inside a check gated by --fast' "$(sed -n '1,120p' validate.sh)")"
assert "remedy registry has 77a" yes "$(has '[77a]=' "$(cat system/scripts/validate-remedies.sh)")"
assert "remedy registry has 77b" yes "$(has '[77b]=' "$(cat system/scripts/validate-remedies.sh)")"
assert "check-selector maps a mods/ source to 77" yes "$(has 77 "$(printf '%s\n' mods/_shared/hooks/run.ts | bash system/scripts/check-selector.sh)")"
assert "check-selector maps mods-check.sh to 77" yes "$(has 77 "$(printf '%s\n' system/scripts/mods-check.sh | bash system/scripts/check-selector.sh)")"
assert "check-selector maps a bad-* fixture to 77" yes "$(has 77 "$(printf '%s\n' tests/fixtures/mods/bad-calls-model/hooks/register.ts | bash system/scripts/check-selector.sh)")"

# validate.sh itself does not run to completion on macOS (pre-existing: test-validate-check-filter.sh
# loses its later checks there the same way; the macOS CI job never calls validate.sh by design).
# 77a's rules reach macOS through test-mods-check.sh; the validate-driven half below is Linux-proven.
# On failure, show validate's tail so the cause is visible in CI logs (they only carry assertions).
if [ "$(uname -s)" = Darwin ] && [ -z "${BRANA_VALIDATE_ON_DARWIN:-}" ]; then
    echo "  SKIP: validate.sh runs on Linux only (see t-3463); static half covered by test-mods-check.sh"
    echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]; exit
fi
echo "--- --fast: 77a runs, 77b warned"
OUT="$(./validate.sh --check 77 --fast 2>&1)"
assert "77a passes under --fast" yes "$(has 'PASS: Check 77a' "$OUT")"
assert "77b is skipped with a WARN under --fast" yes "$(has 'WARN: Check 77b: skipped' "$OUT")"
assert "no FAIL under --fast" no "$(has 'FAIL: Check 77' "$OUT")"

echo "--- no claude on PATH: 77a still runs, 77b FAILS"
OUT="$(PATH="$(path_without claude)" ./validate.sh --check 77 2>&1)"
assert "77a passes without claude" yes "$(has 'PASS: Check 77a' "$OUT")"
assert "77b FAILS without claude" yes "$(has 'FAIL: Check 77b' "$OUT")"
assert "...with the documented message" yes "$(has 'claude CLI not on PATH — install it or run with --fast' "$OUT")"
assert "validate exits non-zero" yes "$(has 'VALIDATION FAILED' "$OUT")"

if command -v claude >/dev/null 2>&1; then
echo "--- claude present: both pass on this checkout"
OUT="$(./validate.sh --check 77 2>&1)"
assert "77a passes" yes "$(has 'PASS: Check 77a' "$OUT")"
assert "77b passes" yes "$(has 'PASS: Check 77b' "$OUT")"
assert "validate exits zero" yes "$(has 'VALIDATION PASSED' "$OUT")"
fi

[ "$FAIL" -eq 0 ] || { echo "--- last validate output (tail)"; printf '%s\n' "${OUT:-}" | tail -25; }
echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
