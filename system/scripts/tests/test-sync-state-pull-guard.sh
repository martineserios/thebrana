#!/usr/bin/env bash
# Tests for sync-state.sh cmd_pull's active_epic contamination guard (t-2297 / ADR-066).
# Mirrors cmd_push's existing t-1883 guard, reversed: pull (repo -> cache) must not
# clobber a foreign active_epic already sitting in the global cache with thebrana's
# own repo value. Hermetic via BRANA_STATE_DIR + HOME overrides.

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

setup_case() {  # repo_epic, cache_epic
    rm -rf "$TMP/state" "$TMP/home"
    mkdir -p "$TMP/state" "$TMP/home/.claude"
    if [ -n "$1" ]; then
        printf '{"active_epic":"%s"}\n' "$1" > "$TMP/state/tasks-config.json"
    fi
    if [ -n "$2" ]; then
        printf '{"active_epic":"%s"}\n' "$2" > "$TMP/home/.claude/tasks-config.json"
    fi
}

run_pull() {
    BRANA_STATE_DIR="$TMP/state" HOME="$TMP/home" bash "$SYNC" pull >/dev/null 2>&1 || true
}

echo "== sync-state.sh cmd_pull active_epic guard =="

# 1. Foreign value in cache, thebrana has its own repo value: pull must NOT clobber
#    the foreign cache value with thebrana's repo value.
setup_case "thebrana-epic" "foreign-epic"
run_pull
check "foreign cache value preserved (not clobbered)" \
    "foreign-epic" \
    "$(jq -r '.active_epic // empty' "$TMP/home/.claude/tasks-config.json" 2>/dev/null)"

# 2. First-run seeding: no prior cache value at all -- pull SHOULD seed normally
#    (the guard must not block legitimate first-time machine setup).
setup_case "thebrana-epic" ""
run_pull
check "first-run seeds cache from repo (no prior value to protect)" \
    "thebrana-epic" \
    "$(jq -r '.active_epic // empty' "$TMP/home/.claude/tasks-config.json" 2>/dev/null)"

# 3. Cache already matches repo value: pull is a no-op for this key (nothing to guard).
setup_case "same-epic" "same-epic"
run_pull
check "matching values: no-op" \
    "same-epic" \
    "$(jq -r '.active_epic // empty' "$TMP/home/.claude/tasks-config.json" 2>/dev/null)"

echo ""
echo "== $PASS/$TOTAL passed =="
[ "$FAIL" -eq 0 ]
