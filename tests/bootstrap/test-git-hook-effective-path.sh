#!/usr/bin/env bash
# Tests for git pre-commit deployment to the EFFECTIVE hooksPath (t-2468).
#
# bootstrap.sh Step 4d deployed the pre-commit template to ~/.config/git/hooks
# and then only inspected the GLOBAL core.hooksPath. git resolves the effective
# path differently: a repo-LOCAL core.hooksPath overrides the global, and a repo
# with neither falls back to its own .git/hooks.
#
# thebrana has a repo-local core.hooksPath pointing at .git/hooks, which shadowed
# the correctly-deployed copy. The active hook was months stale and lacked the
# red-verification call (t-2216), so ADR-061's Stage-2 registration was inert for
# every build while ADR-061 and build-loop.md both claimed the gap was closed.
#
# Coverage:
#   - the tracked template actually invokes red-verification.sh
#   - bootstrap syncs the template into a repo-local core.hooksPath dir
#   - bootstrap syncs into .git/hooks when no hooksPath is configured
#   - the active hook in THIS repo invokes red-verification.sh (live guard)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE="$REPO_ROOT/system/scripts/git-hooks/pre-commit"

PASS=0; FAIL=0; TOTAL=0

ok()   { PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
bad()  { FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; }

echo "=== git pre-commit effective-hooksPath deployment (t-2468) ==="

# 1. The template must actually call red-verification.
if grep -q 'red-verification' "$TEMPLATE"; then
    ok "template invokes red-verification.sh"
else
    bad "template does NOT invoke red-verification.sh — ADR-061 Stage 2 is inert"
fi

# 2/3. bootstrap must sync into the effective hooks dir.
#      Exercised against throwaway repos so the real config is untouched.
run_bootstrap_in() {
    # $1 = repo dir. Runs bootstrap --check and reports whether it would touch
    # the repo's effective hook path.
    ( cd "$1" && HOME="$1/fakehome" bash "$REPO_ROOT/bootstrap.sh" --check 2>&1 )
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

make_repo() {
    local d="$TMP/$1"
    mkdir -p "$d/fakehome" && git -C "$d" init -q 2>/dev/null || git init -q "$d"
    git -C "$d" config user.email t@t && git -C "$d" config user.name t
    echo "$d"
}

# 2. repo-local core.hooksPath override
R1=$(make_repo local-override)
mkdir -p "$R1/custom-hooks"
git -C "$R1" config core.hooksPath "$R1/custom-hooks"
OUT1=$(run_bootstrap_in "$R1")
if grep -q 'effective' <<<"$OUT1"; then
    ok "bootstrap targets a repo-local core.hooksPath override"
else
    bad "bootstrap ignored a repo-local core.hooksPath override"
    echo "        output: $(tr '\n' ' ' <<<"$OUT1" | tail -c 300)"
fi

# 3. no hooksPath configured -> .git/hooks fallback
R2=$(make_repo no-hookspath)
OUT2=$(run_bootstrap_in "$R2")
if grep -q 'effective' <<<"$OUT2"; then
    ok "bootstrap targets .git/hooks when no hooksPath is set"
else
    bad "bootstrap ignored the .git/hooks fallback"
    echo "        output: $(tr '\n' ' ' <<<"$OUT2" | tail -c 300)"
fi

# 4. Live guard: whatever hook is ACTIVE for this repo must call red-verification.
ACTIVE=$(git -C "$REPO_ROOT" config --get core.hooksPath 2>/dev/null || echo "")
if [ -z "$ACTIVE" ]; then
    ACTIVE="$(git -C "$REPO_ROOT" rev-parse --git-common-dir 2>/dev/null)/hooks"
fi
if [ -f "$ACTIVE/pre-commit" ]; then
    if grep -q 'red-verification' "$ACTIVE/pre-commit"; then
        ok "active hook ($ACTIVE/pre-commit) invokes red-verification.sh"
    else
        bad "active hook ($ACTIVE/pre-commit) is STALE — run ./bootstrap.sh"
    fi
else
    bad "no active pre-commit hook found at $ACTIVE/pre-commit"
fi

echo ""
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
