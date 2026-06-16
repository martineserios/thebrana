#!/usr/bin/env bash
# Tests for hybrid recall (brana recall / HybridProvider) in session-start.sh
# Validates that brana recall is called at session start and its results surface
# in additionalContext under [Hybrid recall].
#
# These tests FAIL before the session-start.sh implementation (t-2096) — correct TDD.
#
# Usage: bash test-session-start-hybrid-recall.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../session-start.sh"
PASS=0
FAIL=0
TOTAL=0
TMPDIR_TEST=$(mktemp -d)

trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ── Fake HOME ────────────────────────────────────────────
FAKE_HOME="$TMPDIR_TEST/fakehome"
mkdir -p "$FAKE_HOME/.claude/projects/fake/memory"
echo "# Auto Memory" > "$FAKE_HOME/.claude/projects/fake/memory/MEMORY.md"

# ── Mock brana binary ─────────────────────────────────────
# Returns deterministic JSON for `brana recall` so we can assert on the result.
# All other brana commands return exit 1 (graceful degradation in the hook).
MOCK_BIN_DIR="$TMPDIR_TEST/bin-recall"
mkdir -p "$MOCK_BIN_DIR"
cat > "$MOCK_BIN_DIR/brana" <<'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == "recall" ]]; then
    echo '[{"doc":{"MemoryFile":{"path":"/fake/memory/pattern_test.md","slug":"hybrid-recall-pattern","mtype":"pattern","scope":"project"}},"snippet":"always write tests before implementing code","rrf_score":0.09},{"doc":{"MemoryFile":{"path":"/fake/memory/feedback_test.md","slug":"hybrid-recall-feedback","mtype":"feedback","scope":"project"}},"snippet":"prefer simple solutions over abstractions","rrf_score":0.07}]'
    exit 0
fi
# brana-query fast-path used by task injection — fail silently
if [[ "${1:-}" == "skills" ]] || [[ "${1:-}" == "session" ]] || [[ "${1:-}" == "handoff" ]] || [[ "${1:-}" == "memory" ]]; then
    exit 1
fi
exit 1
MOCK
chmod +x "$MOCK_BIN_DIR/brana"

# Mock brana that fails on recall (for degradation tests)
MOCK_FAIL_DIR="$TMPDIR_TEST/bin-fail"
mkdir -p "$MOCK_FAIL_DIR"
cat > "$MOCK_FAIL_DIR/brana" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
chmod +x "$MOCK_FAIL_DIR/brana"

# ── PATH setup ───────────────────────────────────────────
SAFE_BASE="/usr/bin:/bin:/usr/sbin:/sbin"
GIT_PATH_DIR="$(dirname "$(command -v git)")"
[[ ":$SAFE_BASE:" != *":$GIT_PATH_DIR:"* ]] && SAFE_BASE="$GIT_PATH_DIR:$SAFE_BASE"
JQ_PATH_DIR="$(dirname "$(command -v jq)")"
[[ ":$SAFE_BASE:" != *":$JQ_PATH_DIR:"* ]] && SAFE_BASE="$JQ_PATH_DIR:$SAFE_BASE"

MOCK_PATH="$MOCK_BIN_DIR:$SAFE_BASE"
FAIL_PATH="$MOCK_FAIL_DIR:$SAFE_BASE"

# ── Helpers ──────────────────────────────────────────────

run_hook() {
    local input="$1" path="${2:-$MOCK_PATH}"
    local raw
    raw=$(echo "$input" | \
        PATH="$path" \
        HOME="$FAKE_HOME" \
        BRANA_HOOK_PROFILE=standard \
        CLAUDE_PLUGIN_DATA="" \
        CLAUDE_PLUGIN_ROOT="" \
        CLAUDE_ENV_FILE="" \
        BRANA_RECAP_OFF="1" \
        bash "$HOOK" 2>/dev/null)
    echo "$raw" | grep -E '^\{' | head -1
}

setup_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main 2>/dev/null
    git -C "$dir" config user.email "test@test.com"
    git -C "$dir" config user.name "Test"
    echo "init" > "$dir/init.txt"
    git -C "$dir" add -A && git -C "$dir" commit -q -m "init" 2>/dev/null
}

make_input() {
    local session_id="$1" cwd="$2" effort="${3:-normal}"
    printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SessionStart","matcher":{},"effort":{"level":"%s"}}' \
        "$session_id" "$cwd" "$effort"
}

# ── Test repo ────────────────────────────────────────────
REPO="$TMPDIR_TEST/recall-proj"
setup_repo "$REPO"

echo "Session Start — Hybrid Recall Tests (t-2096)"
echo "============================================="

# ── 1. Results surface in additionalContext ──────────────

echo ""
echo "--- Recall result injection ---"

TOTAL=$((TOTAL + 1))
OUTPUT=$(run_hook "$(make_input "sess-recall-1" "$REPO")")
CTX=$(echo "$OUTPUT" | jq -r '.additionalContext // ""' 2>/dev/null)
# The hook must surface results under a [Hybrid recall] section.
# The slug or snippet from the mock output must appear.
if echo "$CTX" | grep -qiE "Hybrid recall|hybrid-recall-pattern|write tests before"; then
    echo "  PASS: brana recall results surface in additionalContext"
    PASS=$((PASS + 1))
else
    echo "  FAIL: brana recall results NOT in additionalContext"
    echo "    context: $(echo "$CTX" | head -20)"
    FAIL=$((FAIL + 1))
fi

# ── 2. Hook still returns continue=true with recall ──────

TOTAL=$((TOTAL + 1))
if echo "$OUTPUT" | jq -e '.continue == true' >/dev/null 2>&1; then
    echo "  PASS: Hook returns continue=true with hybrid recall active"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Hook did not return continue=true"
    echo "    got: $OUTPUT"
    FAIL=$((FAIL + 1))
fi

# ── 3. Graceful degradation on brana recall failure ──────

echo ""
echo "--- Graceful degradation ---"

TOTAL=$((TOTAL + 1))
FAIL_OUTPUT=$(run_hook "$(make_input "sess-recall-fail" "$REPO")" "$FAIL_PATH")
if echo "$FAIL_OUTPUT" | jq -e '.continue == true' >/dev/null 2>&1; then
    echo "  PASS: brana recall failure degrades gracefully (continue=true)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: brana recall failure caused hook to crash"
    echo "    got: $FAIL_OUTPUT"
    FAIL=$((FAIL + 1))
fi

# ── 4. Low effort level skips recall ─────────────────────

echo ""
echo "--- Effort level gating ---"

TOTAL=$((TOTAL + 1))
LOW_OUTPUT=$(run_hook "$(make_input "sess-recall-low" "$REPO" "low")")
LOW_CTX=$(echo "$LOW_OUTPUT" | jq -r '.additionalContext // ""' 2>/dev/null)
if ! echo "$LOW_CTX" | grep -qiE "Hybrid recall|hybrid-recall-pattern|write tests before"; then
    echo "  PASS: Low effort level skips brana recall"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Low effort level should skip brana recall"
    echo "    ctx: $(echo "$LOW_CTX" | head -5)"
    FAIL=$((FAIL + 1))
fi

# ── Summary ──────────────────────────────────────────────
echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
