#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# Brana PostToolUse hook — log significant tool successes during session.
# Wave 1 (#75): correction detection, test-file detection.
# Input:  stdin JSON (session_id, tool_name, tool_input, cwd)
# Output: stdout JSON (minimal — async hook)

# Ensure valid CWD (may be in deleted worktree)
cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // "{}"' 2>/dev/null) || true
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || true
REPO=$(git -C "${CWD:-.}" rev-parse --show-toplevel 2>/dev/null | xargs basename 2>/dev/null) || REPO=""

if [ -n "${SESSION_ID:-}" ] && [ -n "${TOOL_NAME:-}" ]; then
    TS=$(date +%s 2>/dev/null) || TS=0
    DETAIL=""
    OUTCOME="success"

    case "${TOOL_NAME:-}" in
        Bash)
            DETAIL=$(echo "$TOOL_INPUT" | jq -r '.command // empty' 2>/dev/null) || DETAIL=""
            ;;
        Edit|Write)
            DETAIL=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null) || DETAIL=""
            ;;
        Skill)
            DETAIL=$(echo "$TOOL_INPUT" | jq -r '.skill_name // empty' 2>/dev/null) || DETAIL=""
            OUTCOME="skill-invoke"
            ;;
        *)
            DETAIL="${TOOL_NAME:-unknown}"
            ;;
    esac

    # --- Test/lint command detection (Bash only) ---
    TEST_PASS_COUNT=""
    TEST_FAIL_COUNT=""
    if [ "${TOOL_NAME:-}" = "Bash" ] && [ -n "$DETAIL" ]; then
        if echo "$DETAIL" | grep -qE '(^|\s|/)(npm\s+test|npx\s+(jest|vitest|mocha)|bun\s+test|uv\s+run\s+pytest|pytest|python\s+-m\s+pytest|cargo\s+test|go\s+test|make\s+test|\.\/validate\.sh)(\s|$|;|\|)' 2>/dev/null; then
            OUTCOME="test-pass"
            # --- Test signal: parse tool_response for pass/fail counts ---
            RESPONSE=$(echo "$INPUT" | jq -r '.tool_response.content // .tool_response // empty' 2>/dev/null) || RESPONSE=""
            if [ -n "$RESPONSE" ]; then
                # cargo test: "test result: ok. 23 passed; 0 failed"
                if echo "$RESPONSE" | grep -q 'test result:' 2>/dev/null; then
                    TEST_PASS_COUNT=$(echo "$RESPONSE" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | tail -1) || TEST_PASS_COUNT=""
                    TEST_FAIL_COUNT=$(echo "$RESPONSE" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' | tail -1) || TEST_FAIL_COUNT=""
                # pytest: "N passed", "N failed" in summary line (=====...=====)
                elif echo "$RESPONSE" | grep -qE '=+.*=+$' 2>/dev/null; then
                    TEST_PASS_COUNT=$(echo "$RESPONSE" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | tail -1) || TEST_PASS_COUNT=""
                    TEST_FAIL_COUNT=$(echo "$RESPONSE" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' | tail -1) || TEST_FAIL_COUNT=""
                # jest/vitest: "Tests: N passed, M total" or "N failed, M passed"
                elif echo "$RESPONSE" | grep -qE 'Tests:' 2>/dev/null; then
                    TEST_PASS_COUNT=$(echo "$RESPONSE" | grep 'Tests:' | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | tail -1) || TEST_PASS_COUNT=""
                    TEST_FAIL_COUNT=$(echo "$RESPONSE" | grep 'Tests:' | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' | tail -1) || TEST_FAIL_COUNT=""
                fi
                # Default test_fail to 0 when pass count was parsed (all-pass case)
                [ -n "$TEST_PASS_COUNT" ] && [ -z "$TEST_FAIL_COUNT" ] && TEST_FAIL_COUNT="0"
                [ "${TEST_FAIL_COUNT:-0}" -gt 0 ] 2>/dev/null && OUTCOME="test-fail" || true
            fi
        elif echo "$DETAIL" | grep -qE '(^|\s|/)(eslint|flake8|ruff(\s+check)?|pylint|cargo\s+clippy|golangci-lint|shellcheck|biome\s+check|npm\s+run\s+lint|npx\s+eslint)(\s|$|;|\|)' 2>/dev/null; then
            OUTCOME="lint-pass"
        elif echo "$DETAIL" | grep -qE '(^|\s)gh\s+pr\s+create(\s|$)' 2>/dev/null; then
            OUTCOME="pr-create"
        fi
    fi

    SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"

    # --- Correction detection ---
    # If Edit/Write targets a file that was just edited (last event), it's a correction.
    if [ "${TOOL_NAME:-}" = "Edit" ] || [ "${TOOL_NAME:-}" = "Write" ]; then
        if [ -f "$SESSION_FILE" ] && [ -n "$DETAIL" ]; then
            LAST_EDIT=$(tail -1 "$SESSION_FILE" 2>/dev/null | jq -r 'select(.tool == "Edit" or .tool == "Write") | .detail // empty' 2>/dev/null) || LAST_EDIT=""
            if [ -n "$LAST_EDIT" ] && [ "$LAST_EDIT" = "$DETAIL" ]; then
                OUTCOME="correction"
            fi
        fi

        # --- Test-file detection ---
        if echo "$DETAIL" | grep -qE '(\.test\.|\.spec\.|/tests/|/test/|test_|_test\.)' 2>/dev/null; then
            OUTCOME="test-write"
        fi
    fi

    # --- Clear cascade flag on success ---
    # If a previously-cascading file succeeds, remove the flag to stop warning fatigue.
    if [ "${TOOL_NAME:-}" = "Edit" ] || [ "${TOOL_NAME:-}" = "Write" ]; then
        if [ -n "$SESSION_ID" ] && [ -n "$DETAIL" ]; then
            PATH_HASH=$(echo -n "$DETAIL" | md5sum 2>/dev/null | cut -c1-12) || PATH_HASH=$(echo "$DETAIL" | tr '/' '-' | sed 's/^-//')
            rm -f "/tmp/brana-cascade/${SESSION_ID}-${PATH_HASH}" 2>/dev/null || true
        fi
    fi

    jq -n -c \
        --argjson ts "${TS:-0}" \
        --arg tool "${TOOL_NAME:-unknown}" \
        --arg outcome "$OUTCOME" \
        --arg detail "${DETAIL:-unknown}" \
        --arg repo "${REPO:-}" \
        --arg test_pass "${TEST_PASS_COUNT:-}" \
        --arg test_fail "${TEST_FAIL_COUNT:-}" \
        '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail, repo: $repo}
         + (if $test_pass != "" then {test_pass: ($test_pass | tonumber)} else {} end)
         + (if $test_fail != "" then {test_fail: ($test_fail | tonumber)} else {} end)' \
        >> "$SESSION_FILE" 2>/dev/null || true
fi

echo '{"continue": true}'
