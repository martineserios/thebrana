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

# --- Test 9: companion file sync via push ---
echo ""
echo "companion file sync:"
PORTFOLIO="$HOME/.claude/tasks-portfolio.json"
if [ -f "$PORTFOLIO" ]; then
    # Get first project path from portfolio
    FIRST_PROJECT=$(jq -r '
        if .clients then .clients[0].projects[0].path
        elif .projects then .projects[0].path
        else empty end
    ' "$PORTFOLIO" 2>/dev/null | sed "s|^~|$HOME|") || FIRST_PROJECT=""

    if [ -n "$FIRST_PROJECT" ] && [ -d "$FIRST_PROJECT" ]; then
        PROJECT_NAME=$(basename "$FIRST_PROJECT")
        CC_DIR=""
        for projdir in "$HOME"/.claude/projects/*/; do
            if [ -d "${projdir}memory" ] && grep -qi "$PROJECT_NAME" "${projdir}memory/MEMORY.md" 2>/dev/null; then
                CC_DIR="${projdir}memory"
                break
            fi
        done

        if [ -n "$CC_DIR" ] && [ -f "$CC_DIR/sessions.md" ]; then
            REPO_MEMORY="$FIRST_PROJECT/.claude/memory"
            mkdir -p "$REPO_MEMORY" 2>/dev/null || true

            # Save original if exists
            [ -f "$REPO_MEMORY/sessions.md" ] && cp "$REPO_MEMORY/sessions.md" "/tmp/test-sessions-backup-$$.md"

            output=$(run_sync push)
            if [ -f "$REPO_MEMORY/sessions.md" ]; then
                if cmp -s "$CC_DIR/sessions.md" "$REPO_MEMORY/sessions.md"; then
                    pass "push syncs companion sessions.md to project repo"
                else
                    fail "sessions.md content mismatch after push"
                fi
            else
                fail "sessions.md not synced to project repo"
            fi

            # Restore original
            if [ -f "/tmp/test-sessions-backup-$$.md" ]; then
                mv "/tmp/test-sessions-backup-$$.md" "$REPO_MEMORY/sessions.md"
            fi
        else
            pass "companion sync — skipped (no sessions.md in CC memory for $PROJECT_NAME)"
        fi
    else
        pass "companion sync — skipped (no valid project path in portfolio)"
    fi
else
    pass "companion sync — skipped (no portfolio file)"
fi

# --- Test 10: snapshot creates MEMORY-snapshot.md ---
echo ""
echo "snapshot output:"
SNAPSHOT_DIR="$REPO_ROOT/.claude/memory"
mkdir -p "$SNAPSHOT_DIR" 2>/dev/null || true
# Save original if exists
[ -f "$SNAPSHOT_DIR/MEMORY-snapshot.md" ] && cp "$SNAPSHOT_DIR/MEMORY-snapshot.md" "/tmp/test-snapshot-backup-$$.md"

output=$(run_sync snapshot "$REPO_ROOT")
if [ -f "$SNAPSHOT_DIR/MEMORY-snapshot.md" ]; then
    pass "snapshot creates MEMORY-snapshot.md"
else
    # May not exist if no CC MEMORY.md found for this project
    if echo "$output" | grep -q "skipped"; then
        pass "snapshot correctly skipped (no MEMORY.md for project)"
    else
        fail "snapshot did not create MEMORY-snapshot.md"
    fi
fi

# Restore
if [ -f "/tmp/test-snapshot-backup-$$.md" ]; then
    mv "/tmp/test-snapshot-backup-$$.md" "$SNAPSHOT_DIR/MEMORY-snapshot.md"
else
    rm -f "$SNAPSHOT_DIR/MEMORY-snapshot.md"
fi

# --- Test 11: import without export file ---
echo ""
echo "import (no export file):"
EXPORT_FILE="$REPO_ROOT/system/state/patterns-export.json"
if [ -f "$EXPORT_FILE" ]; then
    mv "$EXPORT_FILE" "/tmp/test-export-backup-$$.json"
fi
output=$(run_sync import)
if echo "$output" | grep -q "skipped"; then
    pass "import skips gracefully when no export file"
else
    fail "import should report missing export: $output"
fi
[ -f "/tmp/test-export-backup-$$.json" ] && mv "/tmp/test-export-backup-$$.json" "$EXPORT_FILE"

# --- Test 12: import with export file ---
echo ""
echo "import (with export file):"
if [ -f "$EXPORT_FILE" ]; then
    output=$(run_sync import)
    if echo "$output" | grep -qE "(import complete|skipped)"; then
        pass "import runs (completed or skipped if no claude-flow)"
    else
        fail "import unexpected output: $output"
    fi
else
    pass "import with file — skipped (no export file in state/)"
fi

# --- Summary ---
echo ""
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
