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
# A directory-based PATH (/usr/bin:/bin:...) is NOT sufficient isolation:
# on any machine where git/jq happen to live in the same directory as
# npx/npm/node (e.g. a system Node.js package installs npx into /usr/bin,
# right alongside git/jq), that whole directory — npx included — leaks back
# onto PATH. cf-env.sh's last-resort fallback (`command -v npx && CF="npx
# ruflo"`) then fires for real, and every session-start.sh invocation in
# this suite pays a genuine ~5-8s network round-trip to the npm registry
# for a nonexistent "ruflo" package instead of failing instantly — with
# ~10+ invocations in this file that reliably exceeds any sane test
# timeout (t-2622; looked exactly like an infinite hang from the outside).
#
# Fix: build an explicit allowlist bin/ of symlinks to only the tools this
# suite actually needs. Anything not linked here — npx/npm/node included —
# is simply not resolvable, regardless of what shares a directory with git
# or jq on a given machine.
SAFE_BIN="$TMPDIR/safebin"
mkdir -p "$SAFE_BIN"
for _tool in bash sh git jq cat mkdir rm mv cp basename dirname date grep sed awk head tail wc ls chmod find timeout env true false sleep printf tr cut sort; do
    _tool_path=$(command -v "$_tool" 2>/dev/null) && ln -sf "$_tool_path" "$SAFE_BIN/$_tool"
done
SAFE_PATH="$SAFE_BIN"

FAKE_HOME="$TMPDIR/fakehome"
mkdir -p "$FAKE_HOME/.claude/projects/fake/memory"
echo "# Auto Memory" > "$FAKE_HOME/.claude/projects/fake/memory/MEMORY.md"

# Run the hook in an isolated environment
run_hook() {
    local input="$1"
    local extra_env="${2:-}"
    local raw
    # Capture to a file, NOT via `$(...)` on a pipe (t-2622). session-start.sh
    # forks background jobs (Job 1a/1b/1c) that, even correctly redirected to
    # /dev/null and reaped by its own PIDS wait-loop, can still leave a
    # grandchild alive past the point session-start.sh itself exits (observed:
    # an `npm exec`-spawned node process under the npx-ruflo fallback). Any
    # such straggler that inherited the ORIGINAL pipe's write end keeps that
    # pipe open, so `raw=$(... | bash "$HOOK")` never sees EOF and hangs
    # forever — even though the hook process itself already exited cleanly
    # and `timeout` already returned. A regular file has no such waiter: once
    # `timeout` returns we just read whatever is on disk.
    local out_file
    out_file=$(mktemp "${TMPDIR}/run-hook-out.XXXXXX")
    echo "$input" | \
        PATH="$SAFE_PATH" \
        HOME="$FAKE_HOME" \
        BRANA_HOOK_PROFILE=standard \
        CLAUDE_PLUGIN_DATA="" \
        CLAUDE_PLUGIN_ROOT="" \
        CLAUDE_ENV_FILE="${CLAUDE_ENV_FILE:-}" \
        BRANA_RECAP_OFF="" \
        $extra_env \
        timeout -k 2 15 bash "$HOOK" >"$out_file" 2>/dev/null
    raw=$(cat "$out_file" 2>/dev/null)
    rm -f "$out_file"
    # The hook's own PIDS wait-loop budgets ~8s worst case (t-2622 comment in
    # session-start.sh); 15s is a generous ceiling. Without this, a hook-level
    # regression that leaks an open stdout fd (t-2622) hangs the whole suite
    # instead of failing one assertion.
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

# ── 13. Ruflo stale lock cleanup (t-1921) ───────────────

echo ""
echo "--- Ruflo stale lock cleanup ---"

REPO_LOCK="$TMPDIR/lock-proj"
setup_repo "$REPO_LOCK"

# Helper: create a dead PID by starting and killing a subprocess
dead_pid() {
    sleep 60 &
    local p=$!
    kill "$p" 2>/dev/null
    wait "$p" 2>/dev/null || true
    echo "$p"
}

# Test 13a: stale lock (dead PID) → lock file removed
SWARM_DIR_A="$FAKE_HOME/.swarm"
mkdir -p "$SWARM_DIR_A"
DEAD_PID=$(dead_pid)
echo "$DEAD_PID" > "$SWARM_DIR_A/ruflo-mcp.pid"
touch "$SWARM_DIR_A/ruflo-mcp.lock"
run_hook "$(make_session_input "sess-lock-dead" "$REPO_LOCK")" >/dev/null
TOTAL=$((TOTAL + 1))
if [ ! -f "$SWARM_DIR_A/ruflo-mcp.lock" ]; then
    echo "  PASS: Stale lock (dead PID) → lock file removed"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Stale lock (dead PID) → lock file should have been removed"
    FAIL=$((FAIL + 1))
fi
rm -f "$SWARM_DIR_A/ruflo-mcp.pid"

# Test 13b: live lock (live PID) → lock file preserved
mkdir -p "$SWARM_DIR_A"
echo "$$" > "$SWARM_DIR_A/ruflo-mcp.pid"
touch "$SWARM_DIR_A/ruflo-mcp.lock"
run_hook "$(make_session_input "sess-lock-live" "$REPO_LOCK")" >/dev/null
TOTAL=$((TOTAL + 1))
if [ -f "$SWARM_DIR_A/ruflo-mcp.lock" ]; then
    echo "  PASS: Live lock (live PID) → lock file preserved"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Live lock (live PID) → lock file should not have been removed"
    FAIL=$((FAIL + 1))
fi
rm -f "$SWARM_DIR_A/ruflo-mcp.lock" "$SWARM_DIR_A/ruflo-mcp.pid"

# Test 13c: lock with no PID file → lock file removed
mkdir -p "$SWARM_DIR_A"
touch "$SWARM_DIR_A/ruflo-mcp.lock"
# No ruflo-mcp.pid written
run_hook "$(make_session_input "sess-lock-nopid" "$REPO_LOCK")" >/dev/null
TOTAL=$((TOTAL + 1))
if [ ! -f "$SWARM_DIR_A/ruflo-mcp.lock" ]; then
    echo "  PASS: Lock with no PID file → lock file removed"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Lock with no PID file → lock file should have been removed"
    FAIL=$((FAIL + 1))
fi

# Test 13d: no lock file → hook runs cleanly, returns continue
# (no setup needed — FAKE_HOME/.swarm may not exist)
rm -rf "$FAKE_HOME/.swarm"
assert_continue "No lock file → hook continues normally" \
    "$(make_session_input "sess-lock-none" "$REPO_LOCK")"

# ── 14. close-queue dead-man check (t-1979 disposition #1) ──────────────
# Pure-jq staleness check: must fire with NO brana binary on PATH —
# dead cron, missing binary, and unregistered job all manifest as a
# stale queue, and the check must not depend on the thing it monitors.
REPO_CQ="$TMPDIR/cq-proj"
mkdir -p "$REPO_CQ"

CQ_OLD=$(date -u -d '4 days ago' +%Y-%m-%dT%H:%M:%SZ)
CQ_FRESH=$(date -u +%Y-%m-%dT%H:%M:%SZ)

cq_entry() { # $1=id $2=timestamp $3=processed
    printf '{"id":"%s","dedup_key":"p:b:%s","timestamp":"%s","branch":"b","project":"p","git_root":"/tmp","git_range":"a..b","commit_count":1,"snapshot_path":"/tmp/%s.diff","processed":%s,"retry_count":0}' \
        "$1" "$1" "$2" "$1" "$3"
}

printf '{"version":1,"entries":[%s]}' "$(cq_entry cq1 "$CQ_OLD" false)" \
    > "$FAKE_HOME/.claude/close-queue.json"
assert_context_contains "Stale close-queue entry (>3d) → dead-man warning" \
    "Close queue" \
    "$(make_session_input "sess-cq-stale" "$REPO_CQ")"

# fresh unprocessed entry → no warning
printf '{"version":1,"entries":[%s]}' "$(cq_entry cq2 "$CQ_FRESH" false)" \
    > "$FAKE_HOME/.claude/close-queue.json"
TOTAL=$((TOTAL + 1))
OUT_CQ=$(run_hook "$(make_session_input "sess-cq-fresh" "$REPO_CQ")")
if echo "$OUT_CQ" | jq -r '.additionalContext // ""' 2>/dev/null | grep -q "Close queue"; then
    echo "  FAIL: Fresh close-queue entry → no dead-man warning"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: Fresh close-queue entry → no dead-man warning"
    PASS=$((PASS + 1))
fi

# old but processed entry → no warning
printf '{"version":1,"entries":[%s]}' "$(cq_entry cq3 "$CQ_OLD" true)" \
    > "$FAKE_HOME/.claude/close-queue.json"
TOTAL=$((TOTAL + 1))
OUT_CQ=$(run_hook "$(make_session_input "sess-cq-processed" "$REPO_CQ")")
if echo "$OUT_CQ" | jq -r '.additionalContext // ""' 2>/dev/null | grep -q "Close queue"; then
    echo "  FAIL: Processed old close-queue entry → no dead-man warning"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: Processed old close-queue entry → no dead-man warning"
    PASS=$((PASS + 1))
fi
rm -f "$FAKE_HOME/.claude/close-queue.json"

# ── 15. Stale-lifecycle P0/P1 escalation (t-2774/t-2779) ────────────────
# Pure jq read of the weekly job's status file (system/state/, repo-relative,
# not $HOME) — never a live query at session-start (context-budget.md).
REPO_STALE="$TMPDIR/stale-proj"
mkdir -p "$REPO_STALE/system/state"

printf '{"stale_p0p1_count":3,"threshold_days":14,"updated":"2026-08-12"}' \
    > "$REPO_STALE/system/state/stale-lifecycle-status.json"
assert_context_contains "Stale P0/P1 count > 0 → gated warning line" \
    "stale P0/P1" \
    "$(make_session_input "sess-stale-nonzero" "$REPO_STALE")"

# count is 0 → silent (no line at all, matches spec §5's gated-single-line requirement)
printf '{"stale_p0p1_count":0,"threshold_days":14,"updated":"2026-08-12"}' \
    > "$REPO_STALE/system/state/stale-lifecycle-status.json"
TOTAL=$((TOTAL + 1))
OUT_STALE=$(run_hook "$(make_session_input "sess-stale-zero" "$REPO_STALE")")
if echo "$OUT_STALE" | jq -r '.additionalContext // ""' 2>/dev/null | grep -qi "stale P0/P1"; then
    echo "  FAIL: Stale P0/P1 count == 0 → silent, no line"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: Stale P0/P1 count == 0 → silent, no line"
    PASS=$((PASS + 1))
fi

# status file absent → silent, no crash
rm -f "$REPO_STALE/system/state/stale-lifecycle-status.json"
TOTAL=$((TOTAL + 1))
OUT_STALE=$(run_hook "$(make_session_input "sess-stale-absent" "$REPO_STALE")")
if echo "$OUT_STALE" | jq -e '.continue == true' >/dev/null 2>&1 \
    && ! echo "$OUT_STALE" | jq -r '.additionalContext // ""' 2>/dev/null | grep -qi "stale P0/P1"; then
    echo "  PASS: Status file absent → silent, no crash"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Status file absent → silent, no crash"
    FAIL=$((FAIL + 1))
fi

# ── Summary ─────────────────────────────────────────────
echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
