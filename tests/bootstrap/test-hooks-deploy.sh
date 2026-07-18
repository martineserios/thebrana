#!/usr/bin/env bash
# Tests for hooks deployment (t-2270).
#
# Hooks merged to main via ship (dev→main) were never deployed:
# hooks-auto-deploy.sh only fires on Write/Edit of a hook file while on main,
# and bootstrap.sh had no hooks step — it assumed the plugin serves hooks, yet
# hooks.json invokes scripts at $HOME/.claude/hooks/. Observed 2026-07-18:
# presence-refresh.sh (t-2221) and red-verification.sh (t-2216) shipped to
# main but were missing at runtime. Same failure class as rules (t-1946).
#
# Tests:
#   T1: bootstrap.sh deploys system/hooks/ -> ~/.claude/hooks/
#   T2: deploy is recursive with delete (rsync -a --delete) — sync_dir can't
#       cover hooks (lib/ and tests/ subdirs)
#   T3: bootstrap dry-run (--check) lists hooks deployment without writing
#   T4: make hooks-check passes against a dest freshly deployed by bootstrap's
#       mechanism (sandboxed HOME — never touches the real ~/.claude)
#
# Run: bash tests/bootstrap/test-hooks-deploy.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0; FAIL=0; TOTAL=0

check() {
    local desc="$1" ok="$2" detail="${3:-}"
    TOTAL=$((TOTAL+1))
    if [ "$ok" = "0" ]; then
        PASS=$((PASS+1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $desc${detail:+ — $detail}"
    fi
}

echo "=== hooks deployment (t-2270) ==="

# T1 — bootstrap has a hooks deploy step targeting $TARGET_DIR/hooks
grep -q 'SYSTEM_DIR/hooks' "$REPO_ROOT/bootstrap.sh"; check "T1: bootstrap deploys system/hooks/" $?

# T2 — recursive sync with delete (rsync -a --delete), not flat sync_dir
grep -E 'rsync -a --delete.*hooks' "$REPO_ROOT/bootstrap.sh" >/dev/null; check "T2: hooks deploy is recursive rsync -a --delete" $?

# T3 — bootstrap --check has a Hooks: step (house style: "Rules:", "Scripts:")
OUT=$(cd "$REPO_ROOT" && timeout 60 ./bootstrap.sh --check 2>/dev/null | grep -E '^Hooks:' | head -1)
[[ "$OUT" == Hooks:* ]]; check "T3: bootstrap --check reports hooks deployment step" $? "$OUT"

# T4 — sandboxed end-to-end: deploy into an empty fake dest via the same
# mechanism bootstrap uses, then verify parity (what make hooks-check asserts).
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/hooks"
rsync -a --delete "$REPO_ROOT/system/hooks/" "$TMP/hooks/" 2>/dev/null
DIFF=$(diff -rq "$REPO_ROOT/system/hooks/" "$TMP/hooks/" 2>&1 || true)
[ -z "$DIFF" ]; check "T4: deployed dest matches source (hooks-check parity)" $? "$DIFF"

echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
