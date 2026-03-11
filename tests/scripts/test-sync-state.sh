#!/usr/bin/env bash
# test-sync-state.sh — Validate sync-state.sh subcommands
#
# Tests all subcommands against real state files.
# Saves and restores any modified files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC_SCRIPT="$REPO_ROOT/system/scripts/sync-state.sh"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

# Capture both stdout and stderr from a command
run_sync() {
    bash "$SYNC_SCRIPT" "$@" 2>&1 || true
}

echo "=== sync-state.sh Tests ==="
echo ""

# --- Test 0: Script exists and is executable ---
echo "Prerequisites:"
if [ -f "$SYNC_SCRIPT" ]; then
    pass "sync-state.sh exists"
else
    fail "sync-state.sh not found"
    echo "=== $PASS passed, $FAIL failed ==="
    exit 1
fi

if [ -x "$SYNC_SCRIPT" ]; then
    pass "sync-state.sh is executable"
else
    fail "sync-state.sh is not executable"
fi

# --- Test 1: help subcommand ---
echo ""
echo "help:"
output=$(run_sync help)
if echo "$output" | grep -q "Usage:"; then
    pass "help prints usage"
else
    fail "help does not print usage"
fi

# --- Test 2: unknown subcommand fails ---
echo ""
echo "unknown command:"
if bash "$SYNC_SCRIPT" bogus 2>&1; then
    fail "unknown subcommand should exit non-zero"
else
    pass "unknown subcommand exits non-zero"
fi

# --- Test 3: push succeeds (idempotent, no changes) ---
echo ""
echo "push (idempotent):"
output=$(run_sync push)
if echo "$output" | grep -q "push complete"; then
    pass "push completes without error"
else
    fail "push failed: $output"
fi

# --- Test 4: pull succeeds when files already in sync ---
echo ""
echo "pull (files in sync):"
output=$(run_sync pull)
if echo "$output" | grep -q "pull complete"; then
    pass "pull completes when files are identical"
else
    fail "pull crashes when files are identical (set -e + sync_file return 1): $output"
fi

# --- Test 5: pull syncs a changed file ---
echo ""
echo "pull (changed file):"
REPO_STATE="$REPO_ROOT/system/state"
CACHE_CONFIG="$HOME/.claude/tasks-config.json"
if [ -f "$REPO_STATE/tasks-config.json" ] && [ -f "$CACHE_CONFIG" ]; then
    # Save originals
    cp "$CACHE_CONFIG" "/tmp/test-config-backup-$$.json"
    ORIGINAL=$(cat "$REPO_STATE/tasks-config.json")

    # Modify repo version to differ from cache
    echo '{"theme":"minimal","_test_marker":true}' > "$REPO_STATE/tasks-config.json"

    output=$(run_sync pull)
    if echo "$output" | grep -q "synced"; then
        pass "pull reports syncing changed file"
    else
        fail "pull did not report sync: $output"
    fi

    # Verify cache was updated with the test marker
    if grep -q "_test_marker" "$CACHE_CONFIG" 2>/dev/null; then
        pass "cache file has new content after pull"
    else
        fail "cache file was not updated after pull"
    fi

    # Restore originals
    echo "$ORIGINAL" > "$REPO_STATE/tasks-config.json"
    cp "/tmp/test-config-backup-$$.json" "$CACHE_CONFIG"
    rm -f "/tmp/test-config-backup-$$.json"
else
    pass "pull changed file — skipped (no config files)"
fi

# --- Test 6: snapshot for thebrana ---
echo ""
echo "snapshot:"
output=$(run_sync snapshot "$REPO_ROOT")
if echo "$output" | grep -qE "(snapshot|skipped)"; then
    pass "snapshot runs or correctly skips"
else
    # snapshot may produce no output if MEMORY.md is already in sync
    if [ -z "$output" ]; then
        pass "snapshot completed silently (files in sync)"
    else
        fail "snapshot unexpected output: $output"
    fi
fi

# --- Test 7: snapshot without arg fails ---
echo ""
echo "snapshot (no arg):"
output=$(run_sync snapshot)
if echo "$output" | grep -q "requires"; then
    pass "snapshot without arg shows error"
else
    fail "snapshot without arg should report missing argument: $output"
fi

# --- Test 8: export subcommand ---
echo ""
echo "export:"
output=$(run_sync export)
if echo "$output" | grep -qE "(exported|skipped)"; then
    pass "export runs (exported or skipped if no claude-flow)"
else
    fail "export unexpected output: $output"
fi

# --- Summary ---
echo ""
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
