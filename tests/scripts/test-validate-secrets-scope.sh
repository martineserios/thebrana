#!/usr/bin/env bash
# Tests for validate.sh Check 6 (no secrets) scope (t-3023).
#
# Check 6 recursively greps system/ for secret-shaped assignments. Build and
# dependency directories under system/ (cargo target/, node_modules/) are not
# source: they are gitignored, can hold tens of GB, and made every validate.sh
# call — and every test that shells out to it — take minutes once CI built the
# brana binary in-tree. They must be skipped, both for speed and because a
# planted file there is not a repo secret.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }

PROBE_DIR="$REPO_ROOT/system/cli/rust/target/t3023-probe"
mkdir -p "$PROBE_DIR"
trap 'rm -rf "$PROBE_DIR"' EXIT
# Not a .sh file and no '#', so nothing in Check 6's own exclusion filter hides it.
printf 'API_KEY=planted-in-build-dir\n' > "$PROBE_DIR/planted.env"

echo "=== validate.sh Check 6 scope (t-3023) ==="
START=$(date +%s)
OUT=$(bash "$REPO_ROOT/validate.sh" --check 6 </dev/null 2>&1 || true)
ELAPSED=$(( $(date +%s) - START ))

if grep -q "PASS: No secrets detected" <<<"$OUT"; then
  ok "a secret-shaped line under system/cli/rust/target/ is not reported"
else
  bad "Check 6 descended into a build dir" "$(grep -n 'planted\|Potential secrets' <<<"$OUT" | head -3)"
fi
if [ "$ELAPSED" -le 60 ]; then
  ok "Check 6 finished in ${ELAPSED}s (<= 60s)"
else
  bad "Check 6 took ${ELAPSED}s — still crawling build output" ""
fi

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
