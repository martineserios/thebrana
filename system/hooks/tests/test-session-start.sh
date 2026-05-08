#!/usr/bin/env bash
# Tests for session-start.sh hook
# Simulates SessionStart JSON input and checks JSON output + side effects.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../session-start.sh"
PASS=0
FAIL=0
TOTAL=0
TMPDIR=$(mktemp -d)

trap 'rm -rf "$TMPDIR"' EXIT

# ── Test isolation ───────────────────────────────────────
# Create a minimal PATH that has only essential tools (git, jq, awk, etc.)
# but NOT ruflo/claude-flow/npx — prevents cf-env.sh from finding ruflo.
# Also create a fake HOME to isolate from real user state.
SAFE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
# Add git if it's elsewhere
GIT_DIR="$(dirname "$(command -v git)")"
[[ ":$SAFE_PATH:" != *":$GIT_DIR:"* ]] && SAFE_PATH="$GIT_DIR:$SAFE_PATH"
JQ_DIR="$(dirname "$(command -v jq)")"
[[ ":$SAFE_PATH:" != *":$JQ_DIR:"* ]] && SAFE_PATH="$JQ_DIR:$SAFE_PATH"

FAKE_HOME="$TMPDIR/fakehome"
mkdir -p "$FAKE_HOME/.claude/projects/fake/memory"
echo "# Auto Memory" > "$FAKE_HOME/.claude/projects/fake/memory/MEMORY.md"

# Run the hook in an isolated environment
run_hook() {
    local input="$1"
    local extra_env="${2:-}"
    local raw
    raw=$(echo "$input" | \
        PATH="$SAFE_PATH" \
        HOME="$FAKE_HOME" \
        BRANA_HOOK_PROFILE=standard \
        CLAUDE_PLUGIN_DATA="" \
        CLAUDE_PLUGIN_ROOT="" \
        CLAUDE_ENV_FILE="${CLAUDE_ENV_FILE:-}" \
        $extra_env \
        bash "$HOOK" 2>/dev/null)
    # Extract only lines that are valid JSON objects (filter background noise)
    echo "$raw" | grep -E '^\{' | head -1
}

# ── Helpers ──────────────────────────────────────────────

assert_continue() {
    local desc="$1"; shift
    TOTAL=$((TOTAL + 1))
    local output
    output=$(run_hook "$1")
    if echo "$output" | jq -e '.continue == true' >/dev/null 2>&1; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected: continue=true"
        echo "    got:      $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_context_contains() {
    local desc="$1"; shift
    local pattern="$1"; shift
    local input="$1"
    TOTAL=$((TOTAL + 1))
    local output
    output=$(run_hook "$input")
    local ctx
    ctx=$(echo "$output" | jq -r '.additionalContext // ""' 2>/dev/null)
    if echo "$ctx" | grep -qi "$pattern"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected context to contain: $pattern"
        echo "    got context: $ctx"
        FAIL=$((FAIL + 1))
    fi
}

# Setup a minimal git repo
setup_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main 2>/dev/null
    git -C "$dir" config user.email "test@test.com"
    git -C "$dir" config user.name "Test"
    echo "init" > "$dir/init.txt"
    git -C "$dir" add -A && git -C "$dir" commit -q -m "init" 2>/dev/null
}

make_session_input() {
    local session_id="$1"
    local cwd="$2"
    cat <<JSON
{"session_id":"$session_id","cwd":"$cwd","hook_event_name":"SessionStart","matcher":{}}
JSON
}

echo "Session Start Tests"
echo "==================="

# ── 1. Missing/empty input ──────────────────────────────

echo ""
echo "--- Input validation ---"

assert_continue "Empty JSON returns continue" \
    '{}'

assert_continue "Missing session_id returns continue" \
    '{"cwd":"/tmp"}'

assert_continue "Missing cwd returns continue" \
    '{"session_id":"test-123"}'

assert_continue "Empty string session_id returns continue" \
    '{"session_id":"","cwd":"/tmp"}'

assert_continue "Null session_id returns continue" \
    '{"session_id":null,"cwd":"/tmp"}'

# ── 2. Malformed JSON input ─────────────────────────────

echo ""
echo "--- Malformed input ---"

assert_continue "Completely malformed input returns continue" \
    'not json at all'

assert_continue "Truncated JSON returns continue" \
    '{"session_id":"test'

assert_continue "Array instead of object returns continue" \
    '[1, 2, 3]'

# ── 3. Valid input produces valid JSON ──────────────────

echo ""
echo "--- JSON output validity ---"

REPO1="$TMPDIR/repo1"
setup_repo "$REPO1"

TOTAL=$((TOTAL + 1))
OUTPUT=$(run_hook "$(make_session_input "sess-001" "$REPO1")")
if echo "$OUTPUT" | jq -e '.' >/dev/null 2>&1; then
    echo "  PASS: Valid input produces valid JSON"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Valid input produces valid JSON"
    echo "    got: $OUTPUT"
    FAIL=$((FAIL + 1))
fi

assert_continue "Valid input returns continue=true" \
    "$(make_session_input "sess-002" "$REPO1")"

# ── 4. Project name derivation from git root ────────────

echo ""
echo "--- Project name derivation ---"

REPO2="$TMPDIR/my-project"
setup_repo "$REPO2"

# Context readback file should contain the project name
TOTAL=$((TOTAL + 1))
run_hook "$(make_session_input "sess-proj" "$REPO2")" >/dev/null
CONTEXT_FILE="/tmp/brana-context-sess-proj.md"
if [ -f "$CONTEXT_FILE" ] && grep -q "my-project" "$CONTEXT_FILE"; then
    echo "  PASS: Project name derived from git root basename"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Project name derived from git root basename"
    echo "    context file exists: $([ -f "$CONTEXT_FILE" ] && echo yes || echo no)"
    [ -f "$CONTEXT_FILE" ] && echo "    content: $(head -5 "$CONTEXT_FILE")"
    FAIL=$((FAIL + 1))
fi
rm -f "$CONTEXT_FILE"

# Subdirectory resolves to repo root name
REPO3="$TMPDIR/sub-project"
setup_repo "$REPO3"
mkdir -p "$REPO3/src/deep"

TOTAL=$((TOTAL + 1))
run_hook "$(make_session_input "sess-sub" "$REPO3/src/deep")" >/dev/null
CONTEXT_FILE="/tmp/brana-context-sess-sub.md"
if [ -f "$CONTEXT_FILE" ] && grep -q "sub-project" "$CONTEXT_FILE"; then
    echo "  PASS: Subdirectory resolves to repo root name"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Subdirectory resolves to repo root name"
    FAIL=$((FAIL + 1))
fi
rm -f "$CONTEXT_FILE"

# ── 5. Task context injection ───────────────────────────

echo ""
echo "--- Task context injection ---"

REPO4="$TMPDIR/task-proj"
setup_repo "$REPO4"
mkdir -p "$REPO4/.claude"
cat > "$REPO4/.claude/tasks.json" <<'TASKS'
{
  "project": "task-proj",
  "tasks": [
    {"id": "t-001", "type": "task", "subject": "Fix login bug", "status": "pending", "stream": "bugs", "order": 1},
    {"id": "t-002", "type": "task", "subject": "Add tests", "status": "completed", "stream": "roadmap", "order": 2}
  ]
}
TASKS

assert_context_contains "Tasks file detected and summarized" \
    "task-proj" \
    "$(make_session_input "sess-tasks" "$REPO4")"

# No tasks.json → fallback message
REPO5="$TMPDIR/no-tasks"
setup_repo "$REPO5"

assert_context_contains "Missing tasks.json produces fallback" \
    "No tasks.json" \
    "$(make_session_input "sess-notasks" "$REPO5")"

# ── 6. CLAUDE_ENV_FILE writes ───────────────────────────

echo ""
echo "--- Environment variable export ---"

REPO6="$TMPDIR/env-proj"
setup_repo "$REPO6"
ENV_FILE="$TMPDIR/env-output.txt"

TOTAL=$((TOTAL + 1))
CLAUDE_ENV_FILE="$ENV_FILE" run_hook "$(make_session_input "sess-env" "$REPO6")" >/dev/null
if [ -f "$ENV_FILE" ] && grep -q "BRANA_PROJECT=env-proj" "$ENV_FILE" && grep -q "BRANA_SESSION_ID=sess-env" "$ENV_FILE"; then
    echo "  PASS: CLAUDE_ENV_FILE receives project and session vars"
    PASS=$((PASS + 1))
else
    echo "  FAIL: CLAUDE_ENV_FILE receives project and session vars"
    [ -f "$ENV_FILE" ] && echo "    content: $(cat "$ENV_FILE")"
    FAIL=$((FAIL + 1))
fi

# ── 7. Context readback file ────────────────────────────

echo ""
echo "--- Context readback file ---"

REPO7="$TMPDIR/readback-proj"
setup_repo "$REPO7"

TOTAL=$((TOTAL + 1))
run_hook "$(make_session_input "sess-rb" "$REPO7")" >/dev/null
CONTEXT_FILE="/tmp/brana-context-sess-rb.md"
if [ -f "$CONTEXT_FILE" ] && grep -q "# Session Context" "$CONTEXT_FILE" && grep -q "sess-rb" "$CONTEXT_FILE"; then
    echo "  PASS: Context readback file written with session ID"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Context readback file written with session ID"
    FAIL=$((FAIL + 1))
fi
rm -f "$CONTEXT_FILE"

# ── 8. Venture project detection ────────────────────────

echo ""
echo "--- Venture detection ---"

REPO8="$TMPDIR/venture-proj"
setup_repo "$REPO8"
mkdir -p "$REPO8/docs/okrs"

assert_context_contains "Venture project detected via docs/okrs" \
    "Venture" \
    "$(make_session_input "sess-vent" "$REPO8")"

# Non-venture should not contain Venture context
REPO9="$TMPDIR/code-proj"
setup_repo "$REPO9"
mkdir -p "$REPO9/src"

TOTAL=$((TOTAL + 1))
OUTPUT=$(run_hook "$(make_session_input "sess-novent" "$REPO9")")
CTX=$(echo "$OUTPUT" | jq -r '.additionalContext // ""' 2>/dev/null)
if ! echo "$CTX" | grep -qi "Venture"; then
    echo "  PASS: Non-venture project has no venture context"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Non-venture project has no venture context"
    echo "    got: $CTX"
    FAIL=$((FAIL + 1))
fi

# ── 9. Concurrent session isolation ─────────────────────

echo ""
echo "--- Session isolation ---"

TOTAL=$((TOTAL + 1))
run_hook "$(make_session_input "sess-iso-A" "$REPO1")" >/dev/null
run_hook "$(make_session_input "sess-iso-B" "$REPO1")" >/dev/null
CTX_A="/tmp/brana-context-sess-iso-A.md"
CTX_B="/tmp/brana-context-sess-iso-B.md"
if [ -f "$CTX_A" ] && [ -f "$CTX_B" ] && grep -q "sess-iso-A" "$CTX_A" && grep -q "sess-iso-B" "$CTX_B"; then
    echo "  PASS: Concurrent sessions produce isolated context files"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Concurrent sessions produce isolated context files"
    FAIL=$((FAIL + 1))
fi
rm -f "$CTX_A" "$CTX_B"

# ── 10. Non-git directory ───────────────────────────────

echo ""
echo "--- Non-git directory ---"

NONGIT="$TMPDIR/nongit"
mkdir -p "$NONGIT"

assert_continue "Non-git directory returns continue" \
    "$(make_session_input "sess-nongit" "$NONGIT")"

# ── 11. Extra-usage disabled warning (t-1034) ───────────

echo ""
echo "--- Extra-usage disabled warning ---"

REPO_EU="$TMPDIR/eu-proj"
setup_repo "$REPO_EU"

# Fake .claude.json with extra-usage disabled at org level
cat > "$FAKE_HOME/.claude.json" <<'EOF'
{
  "cachedExtraUsageDisabledReason": "org_level_disabled",
  "s1mAccessCache": {
    "some-org-id": {"hasAccess": false, "hasAccessNotAsDefault": false}
  }
}
EOF

assert_context_contains "Extra-usage disabled triggers 1M warning" \
    "Extra-usage" \
    "$(make_session_input "sess-eu-disabled" "$REPO_EU")"

assert_context_contains "Warning includes disabled reason" \
    "org_level_disabled" \
    "$(make_session_input "sess-eu-disabled2" "$REPO_EU")"

assert_context_contains "Warning tells user to run /model" \
    "/model" \
    "$(make_session_input "sess-eu-disabled3" "$REPO_EU")"

# Enabled state → no warning
cat > "$FAKE_HOME/.claude.json" <<'EOF'
{
  "cachedExtraUsageDisabledReason": null
}
EOF

TOTAL=$((TOTAL + 1))
OUTPUT=$(run_hook "$(make_session_input "sess-eu-enabled" "$REPO_EU")")
CTX=$(echo "$OUTPUT" | jq -r '.additionalContext // ""' 2>/dev/null)
if ! echo "$CTX" | grep -qi "Extra-usage"; then
    echo "  PASS: Null reason produces no warning"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Null reason produces no warning"
    echo "    got: $CTX"
    FAIL=$((FAIL + 1))
fi

# Missing .claude.json → no warning (no crash)
rm -f "$FAKE_HOME/.claude.json"

TOTAL=$((TOTAL + 1))
OUTPUT=$(run_hook "$(make_session_input "sess-eu-missing" "$REPO_EU")")
CTX=$(echo "$OUTPUT" | jq -r '.additionalContext // ""' 2>/dev/null)
if echo "$OUTPUT" | jq -e '.continue == true' >/dev/null 2>&1 && ! echo "$CTX" | grep -qi "Extra-usage"; then
    echo "  PASS: Missing .claude.json is safe (no warning, no crash)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Missing .claude.json is safe"
    echo "    got: $OUTPUT"
    FAIL=$((FAIL + 1))
fi

# BRANA_1M_WARN_OFF=1 → no warning even when disabled
cat > "$FAKE_HOME/.claude.json" <<'EOF'
{
  "cachedExtraUsageDisabledReason": "org_level_disabled"
}
EOF

TOTAL=$((TOTAL + 1))
OUTPUT=$(BRANA_1M_WARN_OFF=1 run_hook "$(make_session_input "sess-eu-silenced" "$REPO_EU")" "BRANA_1M_WARN_OFF=1")
CTX=$(echo "$OUTPUT" | jq -r '.additionalContext // ""' 2>/dev/null)
if ! echo "$CTX" | grep -qi "Extra-usage"; then
    echo "  PASS: BRANA_1M_WARN_OFF=1 silences warning"
    PASS=$((PASS + 1))
else
    echo "  FAIL: BRANA_1M_WARN_OFF=1 silences warning"
    echo "    got: $CTX"
    FAIL=$((FAIL + 1))
fi

rm -f "$FAKE_HOME/.claude.json"

# ── 12. Bootstrap restart sentinel ─────────────────────

echo ""
echo "--- Bootstrap restart sentinel ---"

REPO_SEN="$TMPDIR/sentinel-proj"
setup_repo "$REPO_SEN"

SENTINEL_FILE="/tmp/brana-bootstrap-pending-restart"

# Sentinel present → banner surfaced in context
rm -f "$SENTINEL_FILE"
touch "$SENTINEL_FILE"

assert_context_contains "Sentinel present → restart banner in context" \
    "restart CC" \
    "$(make_session_input "sess-sentinel-banner" "$REPO_SEN")"

# Sentinel removed after hook runs
rm -f "$SENTINEL_FILE"
touch "$SENTINEL_FILE"
run_hook "$(make_session_input "sess-sentinel-remove" "$REPO_SEN")" >/dev/null
TOTAL=$((TOTAL + 1))
if [ ! -f "$SENTINEL_FILE" ]; then
    echo "  PASS: Sentinel file removed after hook runs"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Sentinel file not removed after hook runs"
    FAIL=$((FAIL + 1))
fi

# No sentinel → no banner
rm -f "$SENTINEL_FILE"
TOTAL=$((TOTAL + 1))
OUTPUT=$(run_hook "$(make_session_input "sess-no-sentinel" "$REPO_SEN")")
CTX=$(echo "$OUTPUT" | jq -r '.additionalContext // ""' 2>/dev/null)
if ! echo "$CTX" | grep -qi "restart CC"; then
    echo "  PASS: No sentinel → no restart banner"
    PASS=$((PASS + 1))
else
    echo "  FAIL: No sentinel → unexpected restart banner"
    echo "    got: $CTX"
    FAIL=$((FAIL + 1))
fi

# ── Summary ─────────────────────────────────────────────
echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
