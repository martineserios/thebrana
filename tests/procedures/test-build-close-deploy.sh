#!/usr/bin/env bash
# t-1948: the build CLOSE procedure must auto-deploy after merge —
# make hooks-deploy when the merged diff touches system/hooks/, and
# bootstrap.sh --sync-plugin when it touches system/skills|procedures/.
# Both conditional (no-op otherwise). Closes the gap recorded in
# pattern_hook-merge-does-not-autodeploy (2026-06-10).
# Run: bash tests/procedures/test-build-close-deploy.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/effective_body.sh"
BUILD_BODY="$(effective_body_file build "$REPO_ROOT")"

PASS=0
FAIL=0
check() {
    local desc="$1" needle="$2"
    if grep -q "$needle" "$BUILD_BODY"; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (missing: $needle)"; FAIL=$((FAIL + 1))
    fi
}

echo "=== test-build-close-deploy.sh ==="

check "CLOSE runs make hooks-deploy post-merge"            "make hooks-deploy"
check "hooks-deploy is gated on system/hooks/ in the diff" 'grep -q "\^system/hooks/"'
check "CLOSE syncs the plugin cache post-merge"            "bootstrap.sh --sync-plugin"
check "cache sync is gated on skills/procedures in diff"   'system/(skills|procedures)/'
check "deploy step documents the no-op case"               "no-op when"
check "deploy step warns about in-flight sessions"         "[Rr]estart"
check "10c recomputes CHANGED itself (not 10b's shell)"    "ORIG_HEAD"
check "deploy failures stop with explicit error"           "ERROR.*failed"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
