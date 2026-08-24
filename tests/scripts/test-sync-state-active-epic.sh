#!/usr/bin/env bash
# Regression guard for the RETIREMENT of the active_epic contamination guards
# in sync-state.sh (ADR-088, t-3196/t-3207/t-3208 — supersedes t-2469/ADR-066).
#
# This file used to test that push/pull PRESERVED a foreign active_epic value
# against clobbering (t-2469). That guard mechanism no longer exists: active_epic
# is no longer authoritative anywhere (resolve_focus_epic() resolves it from
# task state instead), so there is nothing left to protect — the whole-file
# copy sync-state.sh already does for every other key now applies uniformly to
# active_epic too, no special-casing. This file now asserts:
#   - no active_epic guard code remains in sync-state.sh
#   - push/pull run clean (no crash) with a leftover active_epic key present
#   - the whole-file copy behavior applies uniformly (no special preservation)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC="$REPO_ROOT/system/scripts/sync-state.sh"

PASS=0; FAIL=0; TOTAL=0
ok()  { PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; }

command -v jq >/dev/null 2>&1 || { echo "  SKIP: jq not available"; exit 0; }

# Build an isolated cache ($HOME) + repo state dir, run one subcommand, and
# report the resulting active_epic on each side.
#   $1 subcommand (push|pull)
#   $2 cache tasks-config.json contents
#   $3 repo  tasks-config.json contents
# Echoes "<cache_epic>|<repo_epic>|<exit_code>".
run_sync() {
    local sub="$1" cache_json="$2" repo_json="$3" rc
    local tmp; tmp=$(mktemp -d)
    mkdir -p "$tmp/home/.claude/scheduler" "$tmp/state"
    printf '%s' "$cache_json" > "$tmp/home/.claude/tasks-config.json"
    printf '%s' "$repo_json"  > "$tmp/state/tasks-config.json"

    HOME="$tmp/home" BRANA_STATE_DIR="$tmp/state" \
        bash "$SYNC" "$sub" >/dev/null 2>&1
    rc=$?

    local c r
    c=$(jq -r '.active_epic // empty' "$tmp/home/.claude/tasks-config.json" 2>/dev/null || echo "")
    r=$(jq -r '.active_epic // empty' "$tmp/state/tasks-config.json" 2>/dev/null || echo "")
    rm -rf "$tmp"
    echo "$c|$r|$rc"
}

echo "=== sync-state active_epic guard retirement (ADR-088, t-3196) ==="

if grep -q "active_epic" "$SYNC"; then
    bad "sync-state.sh still references active_epic"
else
    ok "sync-state.sh contains no active_epic reference"
fi

# 1. push runs clean even with differing active_epic values on both sides —
#    no crash, no special guard logic engaging.
out=$(run_sync push '{"active_epic":"cache-value"}' '{"active_epic":"repo-value"}')
rc="${out##*|}"
if [ "$rc" = "0" ]; then
    ok "push exits clean with differing active_epic values present"
else
    bad "push exited $rc with differing active_epic values present"
fi

# 2. pull runs clean, same shape, reverse direction.
out=$(run_sync pull '{"active_epic":"cache-value"}' '{"active_epic":"repo-value"}')
rc="${out##*|}"
if [ "$rc" = "0" ]; then
    ok "pull exits clean with differing active_epic values present"
else
    bad "pull exited $rc with differing active_epic values present"
fi

# 3. push with a keyless cache and a repo value present: since no guard
#    protects active_epic anymore, the whole-file copy applies uniformly —
#    the repo's tasks-config.json is simply overwritten by the cache's
#    content like any other synced key, dropping the repo's stale
#    active_epic. This is the intended new behavior (no special-casing),
#    the opposite of what the retired guard used to do (preserve it).
out=$(run_sync push '{"other":1}' '{"active_epic":"harness-core"}')
r="$(echo "$out" | cut -d'|' -f2)"
if [ -z "$r" ]; then
    ok "push: whole-file copy drops repo's active_epic uniformly, no special-casing"
else
    bad "push: repo's active_epic unexpectedly preserved (got '$r') — guard logic may have regressed back in"
fi

echo ""
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
