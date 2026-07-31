#!/usr/bin/env bash
# ADR-060 deploy invariant for the build CLOSE procedure.
#
# HISTORY — this test used to assert the opposite. t-1948 had CLOSE auto-deploy
# after merge (make hooks-deploy / bootstrap.sh --sync-plugin, conditional on the
# merged diff), closing pattern_hook-merge-does-not-autodeploy. ADR-060 and
# t-2188 then reversed that: feature branches merge to `dev`, which is the
# integration buffer and is NOT live, so there is nothing to deploy at
# integration. `main` is production, and bootstrap.sh carries a from-main guard
# (t-2151) that refuses to deploy from any other branch. Deployment happens only
# at ship — the dev→main promotion in step 14.
#
# So the invariant worth guarding flipped: CLOSE must NOT deploy. The negative
# assertions below are the point of this file — they are what would catch
# auto-deploy being reintroduced on the integration path.
#
# Run: bash tests/procedures/test-build-close-deploy.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/effective_body.sh"
BUILD_BODY="$(effective_body_file build "$REPO_ROOT")"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"

PASS=0
FAIL=0
check() {
    local desc="$1" needle="$2" file="${3:-$BUILD_BODY}"
    if grep -qE "$needle" "$file"; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (missing: $needle)"; FAIL=$((FAIL + 1))
    fi
}
check_absent() {
    local desc="$1" needle="$2" file="${3:-$BUILD_BODY}"
    if grep -qE "$needle" "$file"; then
        echo "  FAIL: $desc (found: $needle)"; FAIL=$((FAIL + 1))
    else
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    fi
}

echo "=== test-build-close-deploy.sh ==="

# ── Integration targets dev, never main ──
check "CLOSE integrates to dev"                        'git checkout dev'
check "CLOSE forbids merging a feature branch to main" '[Nn]ever merge a feature branch directly to main'
check "CLOSE states dev is not live"                   'Nothing on|not live|staging buffer'
check "CLOSE cites ADR-060 for the branch model"       'ADR-060'

# ── No deploy at integration — the actual regression guard ──
# Anchored to the deploy verbs, not to prose: reintroducing auto-deploy would
# have to run one of these, and either appearing as an instruction is a failure.
check "CLOSE has an explicit no-deploy-on-integration step" 'No deploy on integration'
check "CLOSE names the bootstrap from-main guard"      'refuses to deploy|from-main guard|t-2151'
check_absent "CLOSE never runs make hooks-deploy at integration" '^ *make hooks-deploy'
check_absent "CLOSE never runs bootstrap --sync-plugin"          'bootstrap\.sh --sync-plugin'

# ── Deploy happens only at ship (step 14) ──
check "ship promotes dev to main"                      'git checkout main'
check "dev→main is fast-forward only"                  'git merge --ff-only dev'
check "ship deploys via bootstrap.sh from main"        '\./bootstrap\.sh'
check "ship is human-gated, not automatic"             'do NOT auto-execute|human-gated'
check "ship warns about in-flight sessions"            'in flight|in-flight'
check "ff-only rejection stops rather than forces"     'STOP and investigate|do not force'

# ── The guard that makes the above enforceable ──
check "bootstrap.sh refuses to deploy off main" 'BRANA_BOOTSTRAP_FORCE|!= "main"' "$BOOTSTRAP"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
