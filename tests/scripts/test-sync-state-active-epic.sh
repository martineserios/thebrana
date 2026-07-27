#!/usr/bin/env bash
# Tests for the active_epic contamination guards in sync-state.sh (t-2469, ADR-066).
#
# Direction (sync-state.sh header): `push` always writes cache→repo, `pull`
# always writes repo→cache. So the sync that can clobber thebrana's OWN
# project-local active_epic is `push` (cache→repo), despite t-2469's title
# naming cmd_pull.
#
# Both guards compared before/after values but each required the INCOMING value
# to be non-empty:
#
#   push: [ -n "$_cache_epic" ] && [ "$_cache_epic" != "$_repo_epic_before" ]
#   pull: [ -n "$_repo_epic"  ] && [ "$_repo_epic"  != "$_cache_epic_before" ]
#
# That is exactly backwards for the reported case. When the incoming file LACKS
# active_epic, the whole-file copy has already dropped the key from the target —
# and then the `-n` test short-circuits, so the guard restores nothing. ADR-066
# gap 4 correctly cleared active_epic from the global copy as orphaned, which
# made every subsequent push silently blank thebrana's active_epic.
#
# Coverage (both directions):
#   - keyless source must NOT clobber a target that has a value  <- the bug
#   - differing values still warn and preserve the target        <- no regression
#   - equal values are a silent no-op
#   - first-run seeding (target keyless) still works

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
# Echoes "<cache_epic>|<repo_epic>".
run_sync() {
    local sub="$1" cache_json="$2" repo_json="$3"
    local tmp; tmp=$(mktemp -d)
    mkdir -p "$tmp/home/.claude/scheduler" "$tmp/state"
    printf '%s' "$cache_json" > "$tmp/home/.claude/tasks-config.json"
    printf '%s' "$repo_json"  > "$tmp/state/tasks-config.json"

    HOME="$tmp/home" BRANA_STATE_DIR="$tmp/state" \
        bash "$SYNC" "$sub" >/dev/null 2>&1 || true

    local c r
    c=$(jq -r '.active_epic // empty' "$tmp/home/.claude/tasks-config.json" 2>/dev/null || echo "")
    r=$(jq -r '.active_epic // empty' "$tmp/state/tasks-config.json" 2>/dev/null || echo "")
    rm -rf "$tmp"
    echo "$c|$r"
}

echo "=== sync-state active_epic guards (t-2469) ==="

# --- push: cache -> repo ------------------------------------------------------
# 1. THE BUG: cache has no active_epic, repo does. Repo value must survive.
out=$(run_sync push '{"other":1}' '{"active_epic":"harness-core"}')
if [ "${out#*|}" = "harness-core" ]; then
    ok "push: keyless cache does not clobber repo active_epic"
else
    bad "push: keyless cache CLOBBERED repo active_epic (got '${out#*|}')"
fi

# 2. No regression: a differing cache value must still be blocked.
out=$(run_sync push '{"active_epic":"other-project"}' '{"active_epic":"harness-core"}')
if [ "${out#*|}" = "harness-core" ]; then
    ok "push: foreign cache value blocked, repo value preserved"
else
    bad "push: foreign cache value overwrote repo (got '${out#*|}')"
fi

# 3. Equal values — no-op.
out=$(run_sync push '{"active_epic":"harness-core"}' '{"active_epic":"harness-core"}')
if [ "${out#*|}" = "harness-core" ]; then
    ok "push: equal values are a no-op"
else
    bad "push: equal values changed repo (got '${out#*|}')"
fi

# 4. First-run seeding: repo keyless, cache has a value -> repo may take it.
out=$(run_sync push '{"active_epic":"seeded"}' '{"other":1}')
if [ "${out#*|}" = "seeded" ]; then
    ok "push: first-run seeding into a keyless repo still works"
else
    bad "push: first-run seeding blocked (got '${out#*|}')"
fi

# --- pull: repo -> cache (mirrored guard) ------------------------------------
# 5. Keyless repo must not clobber a cache that has a value.
out=$(run_sync pull '{"active_epic":"other-project"}' '{"other":1}')
if [ "${out%%|*}" = "other-project" ]; then
    ok "pull: keyless repo does not clobber cache active_epic"
else
    bad "pull: keyless repo CLOBBERED cache active_epic (got '${out%%|*}')"
fi

# 6. No regression: differing repo value still blocked.
out=$(run_sync pull '{"active_epic":"other-project"}' '{"active_epic":"harness-core"}')
if [ "${out%%|*}" = "other-project" ]; then
    ok "pull: differing repo value blocked, cache value preserved"
else
    bad "pull: repo value overwrote cache (got '${out%%|*}')"
fi

echo ""
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
