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

# Is this machine oversubscribed badly enough that a wall-clock measurement
# says nothing about the code under test? Threshold is 2x the core count: the
# hook is mostly waiting on subprocesses, so it tolerates a load equal to nproc
# without trouble (measured: 34/34 green at load 17-19 on 8 cores).
_severely_loaded() {
    local cores load
    cores=$(nproc 2>/dev/null) || cores=""
    load=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null | cut -d. -f1) || load=""
    case "${cores}${load}" in *[!0-9]*|"") return 1 ;; esac
    [ "$load" -gt $(( cores * 2 )) ]
}

assert_timing() {
    local label="$1" elapsed="$2" max_ms="$3"
    if [ "$elapsed" -le "$max_ms" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label (${elapsed}ms <= ${max_ms}ms)"
    elif _severely_loaded; then
        # Belt and braces, never a substitute for the fix (t-2988): the budget
        # is met because the hook's synchronous path is bounded, not because
        # this guard is here. It fires only on a measurement that already
        # failed, and only when the box is more than 2x oversubscribed — a
        # regression on an idle or normally busy machine still reports FAIL.
        # Deliberately neither PASS nor FAIL: a timing sample taken under
        # thrashing is missing data, and counting it as a pass would let a real
        # regression through whenever CI happened to be busy.
        echo "  SKIP: $label — took ${elapsed}ms (max ${max_ms}ms) at load $(cut -d' ' -f1 /proc/loadavg) on $(nproc) cores; machine oversubscribed >2x, wall-clock not meaningful"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label — took ${elapsed}ms, max ${max_ms}ms (load $(cut -d' ' -f1 /proc/loadavg), $(nproc) cores)"
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

# ── Test 6: Hook completes within 8s ──
# The 8000ms is not a magic number: Phase 3 waits on its parallel jobs against
# a declared 5000ms deadline (pinned independently by Test 15), so this budget
# says the hook's own synchronous half must stay under ~3s on top of that.
#
# It used to fail routinely — 33s in the t-2988 report, 85s and 109s when that
# task was picked up — and was read as an over-tight budget flaking under load.
# It was not. The hook was doing ~75s of unbounded synchronous work before it
# emitted a byte: two O(sessions-ever-started) scans of ~/.claude/projects
# (Test 19) and an unbounded `brana skills usage` (Test 20), plus 5s and 3s of
# back-to-back waiting where one 5s deadline was meant. Those are fixed in the
# hook, so this assertion measures what it always claimed to.
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
# TMPDIR_SS is suffixed with the hook's own $$ (t-2969) — glob for it rather
# than the old exact "${SESSION_ID}" path, which the hook no longer creates
# and would otherwise make the "temp dir cleaned" branch below dead code.
TMPDIR_CHECK=$(compgen -G "/tmp/brana-ss-${SESSION_ID}-*" 2>/dev/null | head -1) || TMPDIR_CHECK=""
if [ -z "$TMPDIR_CHECK" ] && [ -f "$CONTEXT_FILE" ]; then
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
#
# Worth keeping distinct from Test 6 rather than deduplicating: it is the second
# invocation in one test run, which is where the t-2622 orphaned-stdout hang and
# the per-invocation $TMPDIR_SS collision of t-2969 both showed up. A repeat run
# exercises state the first one leaves behind.
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

# ── Test 18: Skill hints section emitted from the hints cache ──
echo ""
echo "Test 18: skill hints appear in additionalContext"
# cwd was hardcoded to the author's checkout — the path does not exist on CI,
# so the hook emitted no skill hints and all three assertions failed there.
#
# Source of the hints changed in t-2988. It used to be a live
# `brana skills usage --days 30` on the hook's synchronous path; that call walks
# every transcript under ~/.claude/projects (29.5s measured) and was half of why
# Tests 6/12 blew their budget. The hook now reads a cache that its own Phase 5
# background block refreshes, so this test gates on the cache — the input the
# read path actually has — instead of re-running the expensive query itself.
# A clean runner has no cache yet and correctly emits no section: skip loudly
# there rather than fail, and keep asserting where a regression would be real.
#
# The old assertions looked for /brana:close and /brana:build anywhere in
# additionalContext. Both also occur in unrelated sections ("Consider running
# /brana:close to extract learnings"), so they passed without the hints section
# containing either. Assert against the section's own text and the cache's real
# contents instead.
HINTS_CACHE="$HOME/.claude/cache/skill-hints.txt"
if [ -s "$HINTS_CACHE" ]; then
    INPUT=$(jq -n --arg sid "$SESSION_ID-hints" --arg cwd "$REPO_ROOT" '{session_id: $sid, cwd: $cwd}')
    OUTPUT=$(bash "$HOOKS_DIR/session-start.sh" <<< "$INPUT" 2>/dev/null) || OUTPUT='{"continue":true}'
    CTX=$(echo "$OUTPUT" | grep '^{' | head -1 | jq -r '.additionalContext // ""' 2>/dev/null) || CTX=""
    assert_contains "skill hints section present" "$CTX" "[Skill hints]"
    assert_contains "skill hints has usage heading" "$CTX" "Top skills (by usage):"
    # Every cached hint line must reach additionalContext verbatim.
    HINTS_MISSING=""
    while IFS= read -r hint_line; do
        case "$hint_line" in /*) ;; *) continue ;; esac
        [[ "$CTX" == *"$hint_line"* ]] || HINTS_MISSING="${HINTS_MISSING:+$HINTS_MISSING, }$hint_line"
    done < "$HINTS_CACHE"
    if [ -z "$HINTS_MISSING" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: all cached hint lines present in additionalContext"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: cached hint lines missing from additionalContext: $HINTS_MISSING"
    fi
else
    echo "  SKIP: no skill-hints cache under \$HOME — hints cannot be emitted"
fi
rm -f "/tmp/brana-session-${SESSION_ID}-hints.jsonl" "/tmp/brana-context-${SESSION_ID}-hints.md"

# ── Test 19: no O(all-sessions) scan of ~/.claude/projects on the hot path ──
# t-2988 root cause. ~/.claude/projects gains one directory per CC session ever
# started (14,676 on the machine where Tests 6/12 were failing) while only ~57
# of them hold a memory/MEMORY.md. The hook used to walk every entry with a
# `[ -d ]` stat per iteration — 45s of pure stat() churn per scan, run twice,
# synchronously. That, not "system load", is where the 33-109s went.
#
# The invariant: resolve the auto-memory dir by globbing the MEMORY.md files
# themselves (visits ~57 paths), never by iterating the session-dir glob. This
# is a source-shape assertion because the cost is invisible on a fresh $HOME —
# a timing test alone would go green on any machine that has not accumulated
# thousands of session dirs, i.e. exactly the machines where CI runs.
echo ""
echo "Test 19: no full ~/.claude/projects directory scan in hook"
# Strip comment lines first: the fix above documents the pattern it removed,
# and a shape assertion must read code, not the prose explaining it.
DIR_SCANS=$(grep -v '^[[:space:]]*#' "$HOOKS_DIR/session-start.sh" 2>/dev/null \
    | grep -cE 'for [A-Za-z_]+ in "\$HOME"/\.claude/projects/\*/;') || DIR_SCANS=0
if [ "$DIR_SCANS" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "  PASS: no session-dir glob loop (memory files globbed directly)"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $DIR_SCANS loop(s) iterate every ~/.claude/projects entry — O(sessions-ever-started)"
fi

# ── Test 20: every synchronous external CLI call is timeout-bounded ──
# Second half of the t-2988 root cause, and the one that generalises: the hook
# emits its JSON contract synchronously, so any un-timed external invocation on
# that path is an unbounded stall. `brana skills usage --days 30` measured 29.5s
# here (it walks the same 14k session dirs from inside the Rust CLI). A bigger
# magic number in Tests 6/12 would have hidden that; a bound on each call fixes
# the class — no external tool's latency can blow the hook budget again.
#
# Scope is the critical path only: everything after the PHASE 5 marker runs
# backgrounded and disowned, after the JSON is already on stdout, so it is
# deliberately exempt.
echo ""
echo "Test 20: synchronous external CLI calls are timeout-wrapped"
P5_LINE=$(grep -n 'PHASE 5:' "$HOOKS_DIR/session-start.sh" | head -1 | cut -d: -f1) || P5_LINE=""
if [ -z "$P5_LINE" ]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: PHASE 5 marker not found — cannot delimit the critical path"
else
    UNBOUNDED=$(sed -n "1,${P5_LINE}p" "$HOOKS_DIR/session-start.sh" \
        | grep -nE '"\$(BRANA_BIN|BRANA_QUERY|_BRANA_REM|BRANA_RECALL)"' \
        | grep -vE '\[ -[xzn] ' \
        | grep -v 'timeout ') || UNBOUNDED=""
    if [ -z "$UNBOUNDED" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: all synchronous brana invocations are timeout-bounded"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: unbounded synchronous invocation(s):"
        echo "$UNBOUNDED" | sed 's/^/    /'
    fi
fi

# ── Test 21: SCRIPT_DIR resolves before the hook changes directory ──
# The hook cds to /tmp early, then reaches lib/ and scripts/ helpers through
# SCRIPT_DIR. That assignment used to come after the cd, so `dirname` of a
# relative $0 could no longer be cd'd into and SCRIPT_DIR came out empty —
# every helper behind it silently did nothing. Invisible in practice because CC
# and this file both invoke the hook by absolute path, and invisible in output
# because the helpers are all best-effort (t-2988).
#
# Asserted on source order rather than by running the hook twice: a behavioural
# check would have to diff two additionalContext blobs whose recall and flywheel
# sections legitimately differ between runs.
echo ""
echo "Test 21: SCRIPT_DIR assigned before the cd"
SD_LINE=$(grep -n '^SCRIPT_DIR=' "$HOOKS_DIR/session-start.sh" | head -1 | cut -d: -f1) || SD_LINE=""
CD_LINE=$(grep -n '^cd /tmp' "$HOOKS_DIR/session-start.sh" | head -1 | cut -d: -f1) || CD_LINE=""
if [ -n "$SD_LINE" ] && [ -n "$CD_LINE" ] && [ "$SD_LINE" -lt "$CD_LINE" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: SCRIPT_DIR set at line $SD_LINE, before cd at line $CD_LINE"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: SCRIPT_DIR at line ${SD_LINE:-?} must precede cd at line ${CD_LINE:-?}"
fi

# ── Test 22: the two O(sessions-ever) lookups are cache reads, not scans ──
# Both the skill hints and the auto-memory dir are resolved by walking every
# entry under ~/.claude/projects. Neither can be made cheap in place — you
# cannot tell which of 14,676 session dirs qualifies without touching all of
# them — so the fix is that the hook's synchronous path never does it: Phase 5
# refreshes each cache in the background and Phase 2 only reads (t-2988).
echo ""
echo "Test 22: expensive lookups refreshed in background, not on the hot path"
P5_START=$(grep -n 'PHASE 5:' "$HOOKS_DIR/session-start.sh" | head -1 | cut -d: -f1) || P5_START=""
REFRESH_ON_HOT_PATH=""
for script in skill-hints-refresh.sh memory-dir-cache.sh; do
    # Drop comment lines. The filter has to allow for grep -n's "NNN:" prefix —
    # the Phase 2 read comments point at these scripts by name too.
    line=$(grep -n "scripts/$script" "$HOOKS_DIR/session-start.sh" \
        | grep -vE '^[0-9]+:[[:space:]]*#' | head -1 | cut -d: -f1) || line=""
    if [ -z "$line" ]; then
        REFRESH_ON_HOT_PATH="${REFRESH_ON_HOT_PATH:+$REFRESH_ON_HOT_PATH, }$script (not referenced)"
    elif [ -z "$P5_START" ] || [ "$line" -lt "$P5_START" ]; then
        REFRESH_ON_HOT_PATH="${REFRESH_ON_HOT_PATH:+$REFRESH_ON_HOT_PATH, }$script (line $line, before PHASE 5)"
    fi
    [ -x "$HOOKS_DIR/../scripts/$script" ] || REFRESH_ON_HOT_PATH="${REFRESH_ON_HOT_PATH:+$REFRESH_ON_HOT_PATH, }$script (not executable)"
done
if [ -z "$REFRESH_ON_HOT_PATH" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: both cache refreshes run in the PHASE 5 background block"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $REFRESH_ON_HOT_PATH"
fi

# ── Cleanup ──
rm -f "$CONTEXT_FILE"
rm -f "/tmp/brana-session-${SESSION_ID}.jsonl" "/tmp/brana-session-${SESSION_ID}-timing.jsonl" "/tmp/brana-session-${SESSION_ID}-nongit.jsonl" "/tmp/brana-session-${SESSION_ID}-trim.jsonl" "/tmp/brana-session-${SESSION_ID}-nocf.jsonl"
rm -f "/tmp/brana-context-${SESSION_ID}-trim.md" "/tmp/brana-context-${SESSION_ID}-nocf.md"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
