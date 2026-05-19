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
if [[ "$output" == *"Usage:"* ]]; then
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
if [[ "$output" == *"push complete"* ]]; then
    pass "push completes without error"
else
    fail "push failed: $output"
fi

# --- Test 4: pull succeeds when files already in sync ---
echo ""
echo "pull (files in sync):"
output=$(run_sync pull)
if [[ "$output" == *"pull complete"* ]]; then
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
    if [[ "$output" == *"synced"* ]]; then
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
if [[ "$output" == *"snapshot"* || "$output" == *"skipped"* ]]; then
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
if [[ "$output" == *"requires"* ]]; then
    pass "snapshot without arg shows error"
else
    fail "snapshot without arg should report missing argument: $output"
fi

# --- Test 8: export subcommand ---
echo ""
echo "export:"
output=$(run_sync export)
if [[ "$output" == *"exported"* || "$output" == *"skipped"* ]]; then
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
    if [[ "$output" == *"skipped"* ]]; then
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
if [[ "$output" == *"skipped"* ]]; then
    pass "import skips gracefully when no export file"
else
    fail "import should report missing export: $output"
fi
[ -f "/tmp/test-export-backup-$$.json" ] && mv "/tmp/test-export-backup-$$.json" "$EXPORT_FILE"

# --- Test 12: export produces non-empty data for populated namespaces ---
echo ""
echo "export data quality:"
if [ -f "$EXPORT_FILE" ]; then
    knowledge_count=$(jq '.namespaces.knowledge | length' "$EXPORT_FILE" 2>/dev/null) || knowledge_count=0
    if [ "$knowledge_count" -gt 0 ]; then
        pass "export has $knowledge_count knowledge entries (not empty)"
    else
        fail "export knowledge namespace is empty (expected >0)"
    fi
else
    pass "export data quality — skipped (no export file)"
fi

# --- Test 13: export includes session namespace ---
echo ""
echo "export session namespace:"
if [ -f "$EXPORT_FILE" ]; then
    if jq -e '.namespaces | has("session")' "$EXPORT_FILE" >/dev/null 2>&1; then
        pass "export includes session namespace"
    else
        fail "export missing session namespace"
    fi
else
    pass "session namespace — skipped (no export file)"
fi

# --- Test 14: namespace split — no session entries in pattern namespace ---
echo ""
echo "namespace split:"
DB_PATH="$HOME/.swarm/memory.db"
if [ -f "$DB_PATH" ]; then
    session_in_pattern=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM memory_entries WHERE namespace='pattern' AND key LIKE 'session%';" 2>/dev/null) || session_in_pattern=-1
    if [ "$session_in_pattern" -eq 0 ]; then
        pass "no session entries in pattern namespace (clean split)"
    elif [ "$session_in_pattern" -gt 0 ]; then
        fail "found $session_in_pattern session entries in pattern namespace (namespace pollution)"
    else
        pass "namespace split — skipped (couldn't query DB)"
    fi
else
    pass "namespace split — skipped (no memory.db)"
fi

# --- Test 15: import with export file ---
echo ""
echo "import (with export file):"
if [ -f "$EXPORT_FILE" ]; then
    output=$(run_sync import)
    if [[ "$output" == *"import complete"* || "$output" == *"skipped"* ]]; then
        pass "import runs (completed or skipped if no claude-flow)"
    else
        fail "import unexpected output: $output"
    fi
else
    pass "import with file — skipped (no export file in state/)"
fi

# --- Test 16: sanitize_export_json redacts gcloud OAuth tokens ---
echo ""
echo "sanitize_export_json (t-1458):"
TOXIC="/tmp/test-toxic-$$.json"
CLEAN="/tmp/test-clean-$$.json"
cat > "$TOXIC" <<'JSON'
{"exported_at":"2026-01-01T00:00:00Z","namespaces":{"session":[{"key":"s","content":"curl -H 'Bearer ya29.a0AVvZVsojABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz' https://storage.googleapis.com/bucket"}]}}
JSON
cp "$TOXIC" "$CLEAN"

# Source sync-state.sh to access its functions (BASH_SOURCE guard must be in place)
fn_type=$(bash -c "source '$SYNC_SCRIPT' 2>/dev/null; type -t sanitize_export_json" 2>/dev/null) || true
if [[ "$fn_type" == "function" ]]; then
    bash -c "source '$SYNC_SCRIPT' 2>/dev/null; sanitize_export_json '$CLEAN'"
    if grep -q "ya29\." "$CLEAN"; then
        fail "ya29.* token not redacted in sanitized export"
    else
        pass "ya29.* gcloud token redacted by sanitize_export_json"
    fi
    if grep -q "<token>" "$CLEAN"; then
        pass "placeholder <token> present after sanitization"
    else
        fail "no <token> placeholder after sanitization"
    fi
else
    fail "sanitize_export_json function not found in sync-state.sh (t-1458 not implemented)"
fi
rm -f "$TOXIC" "$CLEAN"

# --- Test 17: sanitize_export_json redacts API_KEY/TOKEN/SECRET/PASSWORD/PRIVATE_KEY patterns (t-1460) ---
echo ""
echo "sanitize_export_json extended patterns (t-1460):"
TOXIC2="/tmp/test-toxic2-$$.json"
CLEAN2="/tmp/test-clean2-$$.json"
cat > "$TOXIC2" <<'JSON'
{"exported_at":"2026-01-01T00:00:00Z","namespaces":{"pattern":[
  {"key":"p1","content":"KAPSO_API_KEY=placeholder-api-key-value"},
  {"key":"p2","content":"export SECRET=placeholder-secret-value"},
  {"key":"p3","content":"PASSWORD=placeholder-password-value"},
  {"key":"p4","content":"TOKEN=placeholder-token-value"},
  {"key":"p5","content":"PRIVATE_KEY=placeholder-private-key-value"}
]}}
JSON
cp "$TOXIC2" "$CLEAN2"

fn_type2=$(bash -c "source '$SYNC_SCRIPT' 2>/dev/null; type -t sanitize_export_json" 2>/dev/null) || true
if [[ "$fn_type2" == "function" ]]; then
    bash -c "source '$SYNC_SCRIPT' 2>/dev/null; sanitize_export_json '$CLEAN2'"
    # Values use 'placeholder-*' so pre-commit Check 5 exclusion filter skips these lines
    for kv in "API_KEY=placeholder-api-key-value" "SECRET=placeholder-secret-value" "PASSWORD=placeholder-password-value" "TOKEN=placeholder-token-value" "PRIVATE_KEY=placeholder-private-key-value"; do
        key="${kv%%=*}"
        val="${kv#*=}"
        if grep -q "$val" "$CLEAN2" 2>/dev/null; then
            fail "$key raw value not redacted (found: $val)"
        else
            pass "$key value redacted"
        fi
    done
    if grep -q "<redacted>" "$CLEAN2"; then
        pass "<redacted> placeholder present for new patterns"
    else
        fail "no <redacted> placeholder found after sanitization"
    fi
else
    fail "sanitize_export_json function not found in sync-state.sh"
fi
rm -f "$TOXIC2" "$CLEAN2"

# --- Summary ---
echo ""
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
