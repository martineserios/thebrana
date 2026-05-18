#!/usr/bin/env bash
# Tests for session-end-persist.sh — validates new classify-then-route behavior (t-1264).
#
# Design contract under test (see t-1264):
#   PATTERN_LEARNINGS  — JSON array of learning strings → $HOME/.claude/memory/patterns.md
#   KNOWLEDGE_FINDINGS — JSON array of knowledge strings → $HOME/.claude/memory/knowledge-staging.md
#   Session metrics    → LAYER0_DIR/sessions.md (unchanged)
#   ruflo unavailable (STORED_L1=false) → patterns.md written, NOT pending-learnings.md
#
# TDD markers:
#   [MISSING] = tests expected to fail against current code; pass after t-1264 ships

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$(cd "$SCRIPT_DIR/../../system/hooks" && pwd)"
SCRIPT="$HOOKS_DIR/session-end-persist.sh"

PASS=0; FAIL=0
TEST_ID="persist-$$"

assert_outcome() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1)); echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL: $label — expected '$expected', got '$actual'"
    fi
}

assert_contains() {
    local label="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        PASS=$((PASS + 1)); echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL: $label — not found: '$needle'"
    fi
}

assert_not_contains() {
    local label="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        FAIL=$((FAIL + 1)); echo "  FAIL: $label — unexpectedly found: '$needle'"
    else
        PASS=$((PASS + 1)); echo "  PASS: $label"
    fi
}

assert_file_exists() {
    local label="$1" path="$2"
    if [ -f "$path" ]; then
        PASS=$((PASS + 1)); echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL: $label — file not found: $path"
    fi
}

assert_file_not_exists() {
    local label="$1" path="$2"
    if [ ! -f "$path" ]; then
        PASS=$((PASS + 1)); echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL: $label — file unexpectedly exists: $path"
    fi
}

# Shared minimal env for all runs
base_env() {
    echo "PROJECT=test-project SESSION_ID=$TEST_ID TIMESTAMP=2026-01-01T00:00:00Z"
    echo "TOTAL=5 SUCCESSES=5 FAILURES=0 CORRECTIONS=0 TEST_WRITES=1 CASCADES=0 PR_CREATES=0"
    echo "TEST_PASSES=10 TEST_FAILS=0 LINT_PASSES=5 LINT_FAILS=0 EDITS=3 DELEGATIONS=0"
    echo "CORRECTION_RATE=0.00 AUTO_FIX_RATE=0.00 TEST_WRITE_RATE=0.20 CASCADE_RATE=0.00"
    echo "TEST_PASS_RATE=1.00 LINT_PASS_RATE=1.00"
    echo "TOOLS=Bash FILES=system/hooks/foo.sh"
    echo "SUMMARY_JSON={}"
    echo "STORED_L1=false"
    echo "BRANA_CLI="
}

echo "=== session-end-persist.sh tests ==="
echo ""

# ── Test 1: Pattern learning → patterns.md [MISSING] ──────────────────────────
echo "Test 1: pattern learning written to patterns.md when STORED_L1=false"
FAKE_HOME_1=$(mktemp -d /tmp/brana-test-home-1-XXXXXX)
LAYER0_1=$(mktemp -d /tmp/brana-test-layer0-1-XXXXXX)
mkdir -p "$FAKE_HOME_1/.claude/memory"

(
    export HOME="$FAKE_HOME_1"
    export LAYER0_DIR="$LAYER0_1"
    export STORED_L1=false
    export PATTERN_LEARNINGS='["grep --exclude=FILE works with globs in recursive scans"]'
    export KNOWLEDGE_FINDINGS='[]'
    export PROJECT=test SESSION_ID="$TEST_ID" TIMESTAMP=2026-01-01T00:00:00Z
    export TOTAL=1 SUCCESSES=1 FAILURES=0 CORRECTIONS=0 TEST_WRITES=0 CASCADES=0 PR_CREATES=0
    export TEST_PASSES=0 TEST_FAILS=0 LINT_PASSES=0 LINT_FAILS=0 EDITS=1 DELEGATIONS=0
    export CORRECTION_RATE=0.00 AUTO_FIX_RATE=0.00 TEST_WRITE_RATE=0.00 CASCADE_RATE=0.00
    export TEST_PASS_RATE=N/A LINT_PASS_RATE=N/A
    export TOOLS=Bash FILES=""
    export SUMMARY_JSON="{}"
    export BRANA_CLI=""
    bash "$SCRIPT" 2>/dev/null || true
)

PATTERNS_CONTENT=$(cat "$FAKE_HOME_1/.claude/memory/patterns.md" 2>/dev/null || echo "")
assert_file_exists "patterns.md created" "$FAKE_HOME_1/.claude/memory/patterns.md"
assert_contains "pattern text appears in patterns.md" "$PATTERNS_CONTENT" "grep --exclude=FILE works with globs"
rm -rf "$FAKE_HOME_1" "$LAYER0_1"

# ── Test 2: Knowledge finding → knowledge-staging.md [MISSING] ────────────────
echo ""
echo "Test 2: knowledge finding written to knowledge-staging.md when STORED_L1=false"
FAKE_HOME_2=$(mktemp -d /tmp/brana-test-home-2-XXXXXX)
LAYER0_2=$(mktemp -d /tmp/brana-test-layer0-2-XXXXXX)
mkdir -p "$FAKE_HOME_2/.claude/memory"

(
    export HOME="$FAKE_HOME_2"
    export LAYER0_DIR="$LAYER0_2"
    export STORED_L1=false
    export PATTERN_LEARNINGS='[]'
    export KNOWLEDGE_FINDINGS='["spec-graph requires ontology-constrained extraction to avoid semantic duplicates"]'
    export PROJECT=test SESSION_ID="$TEST_ID" TIMESTAMP=2026-01-01T00:00:00Z
    export TOTAL=1 SUCCESSES=1 FAILURES=0 CORRECTIONS=0 TEST_WRITES=0 CASCADES=0 PR_CREATES=0
    export TEST_PASSES=0 TEST_FAILS=0 LINT_PASSES=0 LINT_FAILS=0 EDITS=1 DELEGATIONS=0
    export CORRECTION_RATE=0.00 AUTO_FIX_RATE=0.00 TEST_WRITE_RATE=0.00 CASCADE_RATE=0.00
    export TEST_PASS_RATE=N/A LINT_PASS_RATE=N/A
    export TOOLS=Bash FILES=""
    export SUMMARY_JSON="{}"
    export BRANA_CLI=""
    bash "$SCRIPT" 2>/dev/null || true
)

KNOWLEDGE_CONTENT=$(cat "$FAKE_HOME_2/.claude/memory/knowledge-staging.md" 2>/dev/null || echo "")
assert_file_exists "knowledge-staging.md created" "$FAKE_HOME_2/.claude/memory/knowledge-staging.md"
assert_contains "knowledge text in knowledge-staging.md" "$KNOWLEDGE_CONTENT" "spec-graph requires ontology-constrained extraction"
rm -rf "$FAKE_HOME_2" "$LAYER0_2"

# ── Test 3: Session metrics → sessions.md unchanged ───────────────────────────
echo ""
echo "Test 3: session metrics still written to LAYER0_DIR/sessions.md"
FAKE_HOME_3=$(mktemp -d /tmp/brana-test-home-3-XXXXXX)
LAYER0_3=$(mktemp -d /tmp/brana-test-layer0-3-XXXXXX)
mkdir -p "$FAKE_HOME_3/.claude/memory"

(
    export HOME="$FAKE_HOME_3"
    export LAYER0_DIR="$LAYER0_3"
    export STORED_L1=false
    export PATTERN_LEARNINGS='["some pattern learning"]'
    export KNOWLEDGE_FINDINGS='[]'
    export PROJECT=test SESSION_ID="$TEST_ID" TIMESTAMP=2026-01-01T00:00:00Z
    export TOTAL=5 SUCCESSES=5 FAILURES=0 CORRECTIONS=1 TEST_WRITES=2 CASCADES=0 PR_CREATES=0
    export TEST_PASSES=10 TEST_FAILS=0 LINT_PASSES=5 LINT_FAILS=0 EDITS=3 DELEGATIONS=0
    export CORRECTION_RATE=0.20 AUTO_FIX_RATE=0.00 TEST_WRITE_RATE=0.40 CASCADE_RATE=0.00
    export TEST_PASS_RATE=1.00 LINT_PASS_RATE=1.00
    export TOOLS=Bash FILES="foo.sh"
    export SUMMARY_JSON="{}"
    export BRANA_CLI=""
    bash "$SCRIPT" 2>/dev/null || true
)

SESSIONS_CONTENT=$(cat "$LAYER0_3/sessions.md" 2>/dev/null || echo "")
assert_file_exists "sessions.md still written" "$LAYER0_3/sessions.md"
assert_contains "session ID in sessions.md" "$SESSIONS_CONTENT" "$TEST_ID"
rm -rf "$FAKE_HOME_3" "$LAYER0_3"

# ── Test 4: ruflo unavailable → patterns.md written, NOT pending-learnings.md [MISSING] ──
echo ""
echo "Test 4: ruflo unavailable → patterns.md written, pending-learnings.md NOT written"
FAKE_HOME_4=$(mktemp -d /tmp/brana-test-home-4-XXXXXX)
LAYER0_4=$(mktemp -d /tmp/brana-test-layer0-4-XXXXXX)
mkdir -p "$FAKE_HOME_4/.claude/memory"

(
    export HOME="$FAKE_HOME_4"
    export LAYER0_DIR="$LAYER0_4"
    export STORED_L1=false
    export PATTERN_LEARNINGS='["set -e plus ((N++)) silently exits on zero counter"]'
    export KNOWLEDGE_FINDINGS='[]'
    export PROJECT=test SESSION_ID="$TEST_ID" TIMESTAMP=2026-01-01T00:00:00Z
    export TOTAL=2 SUCCESSES=2 FAILURES=0 CORRECTIONS=0 TEST_WRITES=1 CASCADES=0 PR_CREATES=0
    export TEST_PASSES=5 TEST_FAILS=0 LINT_PASSES=3 LINT_FAILS=0 EDITS=2 DELEGATIONS=0
    export CORRECTION_RATE=0.00 AUTO_FIX_RATE=0.00 TEST_WRITE_RATE=0.50 CASCADE_RATE=0.00
    export TEST_PASS_RATE=1.00 LINT_PASS_RATE=1.00
    export TOOLS=Bash FILES=""
    export SUMMARY_JSON="{}"
    export BRANA_CLI=""
    bash "$SCRIPT" 2>/dev/null || true
)

PATTERNS_CONTENT_4=$(cat "$FAKE_HOME_4/.claude/memory/patterns.md" 2>/dev/null || echo "")
assert_file_exists "patterns.md written when ruflo unavailable" "$FAKE_HOME_4/.claude/memory/patterns.md"
assert_contains "learning text in patterns.md" "$PATTERNS_CONTENT_4" "set -e plus ((N++))"
assert_file_not_exists "pending-learnings.md NOT written" "$LAYER0_4/pending-learnings.md"
rm -rf "$FAKE_HOME_4" "$LAYER0_4"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
