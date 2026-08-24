#!/usr/bin/env bash
# Regression guard (ADR-088, t-3207/t-3208): active_epic's push/pull
# contamination guards (t-1883, t-2469) are retired along with the shared
# active_epic config file itself — nothing left to contaminate once
# resolve_focus_epic() is the only resolution path. This test asserts the
# guard code is gone AND that push/pull run clean (no crash, no special
# handling) when a leftover active_epic key is present in either config —
# it's now a harmless, inert orphan, not a value requiring protection.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC="$SCRIPT_DIR/../sync-state.sh"
PASS=0
FAIL=0
TOTAL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

check() {
    local label="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1)); echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL: $label"; echo "    expected: $expected"; echo "    actual:   $actual"
    fi
}

echo "== sync-state.sh: active_epic guard code removed =="

TOTAL=$((TOTAL + 1))
if grep -q "active_epic" "$SYNC"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: sync-state.sh still references active_epic"
else
    PASS=$((PASS + 1))
    echo "  PASS: sync-state.sh contains no active_epic reference"
fi

# Push/pull must run clean (no crash) even with a leftover active_epic key
# sitting in the repo or cache config — it's an inert orphan now, not
# something requiring guard logic to protect.
mkdir -p "$TMP/state" "$TMP/home/.claude"
printf '{"active_epic":"stale-repo-value"}\n' > "$TMP/state/tasks-config.json"
printf '{"active_epic":"stale-cache-value"}\n' > "$TMP/home/.claude/tasks-config.json"

BRANA_STATE_DIR="$TMP/state" HOME="$TMP/home" bash "$SYNC" push >/dev/null 2>&1
check "push exits clean with a leftover active_epic key present" "0" "$?"

BRANA_STATE_DIR="$TMP/state" HOME="$TMP/home" bash "$SYNC" pull >/dev/null 2>&1
check "pull exits clean with a leftover active_epic key present" "0" "$?"

echo ""
echo "== $PASS/$TOTAL passed =="
[ "$FAIL" -eq 0 ]
