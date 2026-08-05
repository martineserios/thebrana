#!/usr/bin/env bash
# Test: both ruflo wrappers resolve to the upgraded version (t-2627 / t-2632).
#
# We were pinned to ruflo v3.10.39 with no deliberate reason. This test is
# RED until the global install is upgraded, then GREEN. It also covers the
# sprint-contract findings (2026-08-05, 2-round challenger review):
#   - ruflo-cli.sh has a plain-glob nvm walk (no version sort) and was missed
#     entirely by the original verification plan — checked independently here.
#   - the blast-radius mitigation (21 other ~/enter_thebrana/ projects
#     reference ruflo-mcp.sh by the live main-checkout path) is only real if
#     tested from outside thebrana's own CWD, not asserted in prose.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MCP_SCRIPT="$REPO_ROOT/system/scripts/ruflo-mcp.sh"
CLI_SCRIPT="$REPO_ROOT/system/scripts/ruflo-cli.sh"
PINNED_VERSION="3.10.39"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== ruflo version resolution (t-2627) ==="

# Test 1: ruflo-mcp.sh no longer reports the pinned stale version.
mcp_version="$("$MCP_SCRIPT" --version 2>/dev/null | tr -d '[:space:]')"
if [ -n "$mcp_version" ] && [ "$mcp_version" != "$PINNED_VERSION" ] && [[ "$mcp_version" != *"$PINNED_VERSION"* ]]; then
    pass "ruflo-mcp.sh resolves an upgraded version ($mcp_version)"
else
    fail "ruflo-mcp.sh still resolves the pinned version ($mcp_version) — run: npm install -g ruflo@latest"
fi

# Test 2: ruflo-cli.sh no longer reports the pinned stale version.
# (t-1936's "single sanctioned CLI entry" — a SEPARATE wrapper from ruflo-mcp.sh,
# missed by the original verification plan per the sprint-contract review.)
cli_version="$("$CLI_SCRIPT" --version 2>/dev/null | tr -d '[:space:]')"
if [ -n "$cli_version" ] && [ "$cli_version" != "$PINNED_VERSION" ] && [[ "$cli_version" != *"$PINNED_VERSION"* ]]; then
    pass "ruflo-cli.sh resolves an upgraded version ($cli_version)"
else
    fail "ruflo-cli.sh still resolves the pinned version ($cli_version) — separate nvm-walk from ruflo-mcp.sh, check independently"
fi

# Test 3: both wrappers agree — a mismatch means one is shadowed by a stale
# nvm-installed version (ruflo-cli.sh's plain glob is more shadowing-prone
# than ruflo-mcp.sh's sort -rV walk).
if [ -n "$mcp_version" ] && [ "$mcp_version" = "$cli_version" ]; then
    pass "both wrappers resolve the same version ($mcp_version)"
else
    fail "wrappers disagree — ruflo-mcp.sh=$mcp_version, ruflo-cli.sh=$cli_version (one is shadowed by a stale nvm install)"
fi

# Test 4: external CLAUDE_PROJECT_DIR invocation (simulating one of the 21
# other consumer projects) still resolves the upgraded version. The fixture
# dir MUST pre-exist — ruflo-mcp.sh silently falls back to $HOME otherwise
# (line 19's -d test), which would make this check pass without exercising
# anything (sprint-contract Warning 4).
FAKE_PROJECT="$(mktemp -d)"
external_out="$(CLAUDE_PROJECT_DIR="$FAKE_PROJECT" "$MCP_SCRIPT" --version 2>/tmp/ruflo-version-test-stderr.$$)"
external_version="$(echo "$external_out" | tr -d '[:space:]')"
if [ -n "$external_version" ] && [ "$external_version" != "$PINNED_VERSION" ] && [[ "$external_version" != *"$PINNED_VERSION"* ]]; then
    pass "ruflo-mcp.sh resolves the upgraded version under an external CLAUDE_PROJECT_DIR ($external_version)"
else
    fail "external-CWD invocation did not resolve the upgraded version ($external_version)"
fi

# Test 5: no stale-shadow WARN in stderr during the external-CWD invocation —
# a concrete, scripted check (sprint-contract Warning 1: "no shadowing" was
# previously eyeball-passable rather than scripted).
if grep -q '\[ruflo-mcp\] WARN: ruflo found in nvm' /tmp/ruflo-version-test-stderr.$$ 2>/dev/null; then
    fail "stale-shadow WARN present — ruflo-mcp.sh resolved a non-default nvm install: $(cat /tmp/ruflo-version-test-stderr.$$)"
else
    pass "no stale-shadow WARN in stderr"
fi
rm -f /tmp/ruflo-version-test-stderr.$$
rm -rf "$FAKE_PROJECT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
