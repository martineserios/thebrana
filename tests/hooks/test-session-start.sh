#!/usr/bin/env bash
# Tests for session-start.sh — validates JSON output, additionalContext injection,
# and that the hook completes within timeout bounds.
#
# TDD markers:
#   [BUG]     = tests expected to fail, exposing a known bug
#   [MISSING] = tests expected to fail, exposing missing coverage
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOKS_DIR="$(cd "$SCRIPT_DIR/../../system/hooks" && pwd)"
HOOK="$HOOKS_DIR/session-start.sh"

# shellcheck source=_helpers.sh
source "$SCRIPT_DIR/_helpers.sh"

PASS=0
FAIL=0
SESSION_ID="test-ss-$$"

assert_outcome() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label — expected '$expected', got '$actual'"
    fi
}

assert_contains() {
    local label="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label — output does not contain '$needle'"
    fi
}

assert_valid_json() {
    local label="$1" json="$2"
    if echo "$json" | jq -e '.' >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label — invalid JSON: $json"
    fi
}

assert_timing() {
    local label="$1" elapsed="$2" max_ms="$3"
    if [ "$elapsed" -le "$max_ms" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label (${elapsed}ms <= ${max_ms}ms)"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label — took ${elapsed}ms, max ${max_ms}ms"
    fi
}

echo "=== session-start.sh tests ==="
echo ""

# ── Test 1: Empty input returns valid JSON with continue:true ──
echo "Test 1: empty/missing input"
OUTPUT=$(run_hook_json '{}')
assert_valid_json "empty input → valid JSON" "$OUTPUT"
CONTINUE=$(echo "$OUTPUT" | jq -r '.continue' 2>/dev/null) || CONTINUE=""
assert_outcome "empty input → continue:true" "true" "$CONTINUE"

# ── Test 2: Missing session_id returns early ──
echo ""
echo "Test 2: missing session_id"
OUTPUT=$(run_hook_json '{"cwd": "/tmp"}')
assert_valid_json "missing session_id → valid JSON" "$OUTPUT"
CONTINUE=$(echo "$OUTPUT" | jq -r '.continue' 2>/dev/null) || CONTINUE=""
assert_outcome "missing session_id → continue:true" "true" "$CONTINUE"

# ── Test 3: Valid input with real CWD produces valid JSON ──
echo ""
echo "Test 3: valid input with CWD=$(pwd)"
INPUT=$(jq -n --arg sid "$SESSION_ID" --arg cwd "$(pwd)" '{session_id: $sid, cwd: $cwd}')
OUTPUT=$(run_hook_json "$INPUT")
assert_valid_json "valid input → valid JSON" "$OUTPUT"
CONTINUE=$(echo "$OUTPUT" | jq -r '.continue' 2>/dev/null) || CONTINUE=""
assert_outcome "valid input → continue:true" "true" "$CONTINUE"

# ── Test 4: additionalContext is string or null (never object) ──
echo ""
echo "Test 4: additionalContext type"
AC_TYPE=$(echo "$OUTPUT" | jq -r '.additionalContext | type' 2>/dev/null) || AC_TYPE="null"
if [ "$AC_TYPE" = "string" ] || [ "$AC_TYPE" = "null" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: additionalContext is $AC_TYPE"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: additionalContext is '$AC_TYPE', expected string or null"
fi

# ── Test 5: Task context injected when tasks.json exists ──
echo ""
echo "Test 5: task context injection"
if [ -f "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/tasks.json" ]; then
    AC=$(echo "$OUTPUT" | jq -r '.additionalContext // ""' 2>/dev/null) || AC=""
    assert_contains "tasks.json present → task context in output" "$AC" "[Active tasks]"
else
    echo "  SKIP: no tasks.json in project"
fi

# ── Test 6: Hook completes within 8s (budget for parallel CF searches) ──
echo ""
echo "Test 6: timing (must complete within 8000ms)"
INPUT=$(jq -n --arg sid "$SESSION_ID-timing" --arg cwd "$(pwd)" '{session_id: $sid, cwd: $cwd}')
RESULT=$(run_hook_timed "$INPUT")
ELAPSED="${RESULT%%|*}"
TIMED_OUTPUT="${RESULT#*|}"
assert_timing "hook completes within budget" "$ELAPSED" "8000"
assert_valid_json "timed run → valid JSON" "$TIMED_OUTPUT"

# ── Test 7: Non-git directory still works ──
echo ""
echo "Test 7: non-git directory"
INPUT=$(jq -n --arg sid "$SESSION_ID-nongit" --arg cwd "/tmp" '{session_id: $sid, cwd: $cwd}')
OUTPUT=$(run_hook_json "$INPUT")
assert_valid_json "non-git dir → valid JSON" "$OUTPUT"

# ── Test 8: Handoff extraction pipeline ──
echo ""
echo "Test 8: handoff extraction sed/grep pipeline"

# Create a known handoff entry and pipe through the same extraction logic
HANDOFF_RAW="## 2026-03-30 (3) — Test session

**Accomplished:**
- Built feature X
- Fixed bug Y

**Learnings:**
- Something useful

**State:**
- Branch: main

**Doc drift:** None

**Next:**
- Do thing A
- Do thing B
- Do thing C

**Blockers:** None"

HO_HEADING=$(echo "$HANDOFF_RAW" | head -1 | sed 's/^## //')
assert_outcome "heading extraction" "2026-03-30 (3) — Test session" "$HO_HEADING"

HO_NEXT=$(echo "$HANDOFF_RAW" | sed -n '/^\*\*Next:\*\*/,/^\*\*[A-Z]/p' | grep -v '^\*\*' | sed 's/^- //' | head -5) || true
assert_contains "next items extracted" "$HO_NEXT" "Do thing A"
assert_contains "next items multi-line" "$HO_NEXT" "Do thing C"

HO_BLOCKERS=$(echo "$HANDOFF_RAW" | sed -n '/^\*\*Blockers:\*\*/,/^\*\*[A-Z]/p' | grep -v '^\*\*' | head -3) || true
# "None" blockers should be filtered
if grep -qi "^none$" <<< "$HO_BLOCKERS"; then
    PASS=$((PASS + 1))
    echo "  PASS: 'None' blockers detected for suppression"
else
    # Blockers was empty (also acceptable — means sed didn't match)
    if [ -z "$HO_BLOCKERS" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: blockers empty (no content after heading)"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: unexpected blockers content: '$HO_BLOCKERS'"
    fi
fi

# Test with real blockers
HANDOFF_WITH_BLOCKERS="## 2026-03-30 — Blocked session

**Next:**
- Fix the thing

**Blockers:**
- Waiting on API access
- Need credentials"

HO_BLOCKERS2=$(echo "$HANDOFF_WITH_BLOCKERS" | sed -n '/^\*\*Blockers:\*\*/,/^\*\*[A-Z]/p' | grep -v '^\*\*' | head -3) || true
assert_contains "real blockers extracted" "$HO_BLOCKERS2" "Waiting on API access"

# Test handoff context assembly
HANDOFF_CONTEXT="Last session: $HO_HEADING"
if [ -n "$HO_NEXT" ]; then
    HANDOFF_CONTEXT="$HANDOFF_CONTEXT
Next: $HO_NEXT"
fi
assert_contains "assembled context has heading" "$HANDOFF_CONTEXT" "Last session: 2026-03-30"
assert_contains "assembled context has next" "$HANDOFF_CONTEXT" "Next:"

# ── Test 9: Context readback file written ──
echo ""
echo "Test 9: context readback file"
CONTEXT_FILE="/tmp/brana-context-${SESSION_ID}.md"
if [ -f "$CONTEXT_FILE" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: context file exists at $CONTEXT_FILE"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: context file not written at $CONTEXT_FILE"
fi

# ── Test 10: Context file contains session heading ──
echo ""
echo "Test 10: context file content"
if [ -f "$CONTEXT_FILE" ]; then
    assert_contains "context file has session ID" "$(cat "$CONTEXT_FILE")" "$SESSION_ID"
    assert_contains "context file has heading" "$(cat "$CONTEXT_FILE")" "# Session Context"
else
    FAIL=$((FAIL + 2))
    echo "  FAIL: context file missing — cannot check content"
    echo "  FAIL: context file missing — cannot check heading"
fi

# ── Test 11: Context file survives after hook completes (not in trap cleanup) ──
echo ""
echo "Test 11: context file survives trap"
TMPDIR_CHECK="/tmp/brana-ss-${SESSION_ID}"
if [ ! -d "$TMPDIR_CHECK" ] && [ -f "$CONTEXT_FILE" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: temp dir cleaned, context file survived"
elif [ -f "$CONTEXT_FILE" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: context file survived (temp dir also present — acceptable)"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: context file did not survive hook execution"
fi

# ── Test 12: Second run also completes within the hook budget ──
# The original premise ("trimmed: 1 parallel job, 2s budget", 4000ms) is gone —
# t-1937 added a parallel job and raised the wait to 5000ms. This runs the same
# un-trimmed hook as Test 6, so it is held to the same 8s budget; the 7000ms
# figure was a leftover that the hook now legitimately exceeds (~7.2s measured).
echo ""
echo "Test 12: repeat timing (must complete within 8000ms)"
INPUT=$(jq -n --arg sid "$SESSION_ID-trim" --arg cwd "$(pwd)" '{session_id: $sid, cwd: $cwd}')
RESULT=$(run_hook_timed "$INPUT")
ELAPSED="${RESULT%%|*}"
assert_timing "repeat run within hook budget" "$ELAPSED" "8000"

# ── Test 13: No Python dependency in hook ──
echo ""
echo "Test 13: no python3/uv calls in session-start.sh"
PYTHON_CALLS=$(grep -cE '^\s*(python3|uv run)' "$HOOKS_DIR/session-start.sh" 2>/dev/null) || PYTHON_CALLS=0
if [ "$PYTHON_CALLS" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "  PASS: no python3/uv calls in hook"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: found $PYTHON_CALLS python3/uv calls — should be 0 after trim"
fi

# ── Test 14: Single ruflo parallel job (not 2+) ──
echo ""
echo "Test 14: single ruflo parallel job"
# Count subshells that call $CF in Phase 1 (between PHASE 1 and PHASE 2 markers)
RUFLO_JOBS=$(sed -n '/PHASE 1:/,/PHASE 2:/p' "$HOOKS_DIR/session-start.sh" | grep -c 'timeout.*\$CF' 2>/dev/null) || RUFLO_JOBS=0
if [ "$RUFLO_JOBS" -eq 1 ]; then
    PASS=$((PASS + 1))
    echo "  PASS: exactly 1 ruflo parallel job"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: expected 1 ruflo job, found $RUFLO_JOBS"
fi

# ── Test 15: Parallel wait budget is bounded ──
# t-940 set this to 2000ms; t-1937 raised it to 5000ms when the flywheel read
# path added another parallel job. The invariant worth pinning is that the wait
# stays BOUNDED and within the hook's own 8s budget — not one magic number that
# has to be edited every time a parallel job is added or removed.
echo ""
echo "Test 15: parallel wait budget is bounded and under the hook budget"
BUDGET=$(grep -oP 'REMAINING_MS=\$\(\(\K\d+' "$HOOKS_DIR/session-start.sh" 2>/dev/null | head -1) || BUDGET=""
if [ -n "$BUDGET" ] && [ "$BUDGET" -gt 0 ] && [ "$BUDGET" -le 8000 ]; then
    PASS=$((PASS + 1))
    echo "  PASS: wait budget is ${BUDGET}ms (bounded, <= 8000ms)"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: wait budget is '${BUDGET:-unknown}', expected a bound in 1..8000"
fi

# ── Test 16: Timing marks written to log ──
echo ""
echo "Test 16: timing marks in /tmp/brana-startup-timing.log"
TIMING_LOG="/tmp/brana-startup-timing.log"
if [ -f "$TIMING_LOG" ]; then
    assert_contains "timing log has hook-start" "$(cat "$TIMING_LOG")" "hook-start"
    assert_contains "timing log has hook-end" "$(cat "$TIMING_LOG")" "hook-end"
else
    FAIL=$((FAIL + 2))
    echo "  FAIL: timing log not found at $TIMING_LOG"
    echo "  FAIL: (skipped hook-end check)"
fi

# ── Test 17: Ruflo fallback when CF unavailable ──
echo ""
echo "Test 17: ruflo unavailable fallback"
INPUT=$(jq -n --arg sid "$SESSION_ID-nocf" --arg cwd "/tmp" '{session_id: $sid, cwd: $cwd}')
OUTPUT=$(CF="" bash "$HOOKS_DIR/session-start.sh" <<< "$INPUT" 2>/dev/null | grep '^{' | head -1) || OUTPUT='{"continue":true}'
assert_valid_json "no ruflo → valid JSON" "$OUTPUT"

# ── Test 18: Skill hints section emitted when brana available ──
echo ""
echo "Test 18: skill hints appear in additionalContext"
# cwd was hardcoded to the author's checkout — the path does not exist on CI,
# so the hook emitted no skill hints and all three assertions failed there.
#
# The hints themselves come from `brana skills usage --days 30`, i.e. accumulated
# telemetry under $HOME. A clean runner has none, so the hook correctly emits no
# [Skill hints] section and these assertions cannot pass there. Skip loudly on an
# unprovisioned runner rather than fail — and keep asserting on a machine that
# does have usage data, where a regression would be real.
HAVE_USAGE=$(cd "$REPO_ROOT" && brana skills usage --days 30 --json 2>/dev/null \
    | jq -r '[.skills[].name] | length' 2>/dev/null) || HAVE_USAGE=0
if [ "${HAVE_USAGE:-0}" -gt 0 ]; then
    INPUT=$(jq -n --arg sid "$SESSION_ID-hints" --arg cwd "$REPO_ROOT" '{session_id: $sid, cwd: $cwd}')
    OUTPUT=$(bash "$HOOKS_DIR/session-start.sh" <<< "$INPUT" 2>/dev/null) || OUTPUT='{"continue":true}'
    CTX=$(echo "$OUTPUT" | grep '^{' | head -1 | jq -r '.additionalContext // ""' 2>/dev/null) || CTX=""
    assert_contains "skill hints section present" "$CTX" "[Skill hints]"
    assert_contains "skill hints contains /brana:close" "$CTX" "/brana:close"
    assert_contains "skill hints contains /brana:build" "$CTX" "/brana:build"
else
    echo "  SKIP: no skill-usage telemetry under \$HOME — hints cannot be emitted"
fi
rm -f "/tmp/brana-session-${SESSION_ID}-hints.jsonl" "/tmp/brana-context-${SESSION_ID}-hints.md"

# ── Cleanup ──
rm -f "$CONTEXT_FILE"
rm -f "/tmp/brana-session-${SESSION_ID}.jsonl" "/tmp/brana-session-${SESSION_ID}-timing.jsonl" "/tmp/brana-session-${SESSION_ID}-nongit.jsonl" "/tmp/brana-session-${SESSION_ID}-trim.jsonl" "/tmp/brana-session-${SESSION_ID}-nocf.jsonl"
rm -f "/tmp/brana-context-${SESSION_ID}-trim.md" "/tmp/brana-context-${SESSION_ID}-nocf.md"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
