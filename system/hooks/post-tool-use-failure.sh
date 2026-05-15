#!/usr/bin/env bash
# No strict mode — failure hooks especially must never fail themselves.

# Brana PostToolUseFailure hook — log tool failures during session.
# Wave 1 (#75): error categorization, cascade detection.
# Wave 2 (t-679): cross-session error recurrence tracking via persistent JSONL + ruflo.
# Input:  stdin JSON (session_id, tool_name, tool_input, cwd)
# Output: stdout JSON (minimal — async hook)

# Ensure valid CWD (may be in deleted worktree)
cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true
SESSION_ID="${SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // "{}"' 2>/dev/null) || true
DURATION_MS=$(echo "$INPUT" | jq -r '.duration_ms // 0' 2>/dev/null) || DURATION_MS=0
EFFORT_LEVEL=$(echo "$INPUT" | jq -r '.effort.level // "normal"' 2>/dev/null) || EFFORT_LEVEL="normal"

if [ -n "${SESSION_ID:-}" ] && [ -n "${TOOL_NAME:-}" ]; then
    TS=$(date +%s 2>/dev/null) || TS=0
    DETAIL=""

    case "${TOOL_NAME:-}" in
        Bash)
            DETAIL=$(echo "$TOOL_INPUT" | jq -r '.command // empty' 2>/dev/null) || DETAIL=""
            ;;
        Edit|Write|Read|NotebookEdit|MultiEdit)
            # File-targeted tools — extract the file/notebook path
            DETAIL=$(echo "$TOOL_INPUT" | jq -r '.file_path // .notebook_path // empty' 2>/dev/null) || DETAIL=""
            ;;
        *)
            DETAIL="${TOOL_NAME:-unknown}"
            ;;
    esac

    # --- Test/lint command detection (Bash only) ---
    OUTCOME="failure"
    if [ "${TOOL_NAME:-}" = "Bash" ] && [ -n "$DETAIL" ]; then
        if echo "$DETAIL" | grep -qE '(^|\s|/)(npm\s+test|npx\s+(jest|vitest|mocha)|bun\s+test|pytest|python\s+-m\s+pytest|cargo\s+test|go\s+test|make\s+test|\.\/validate\.sh)(\s|$|;|\|)' 2>/dev/null; then
            OUTCOME="test-fail"
        elif echo "$DETAIL" | grep -qE '(^|\s|/)(eslint|flake8|ruff(\s+check)?|pylint|cargo\s+clippy|golangci-lint|shellcheck|biome\s+check|npm\s+run\s+lint|npx\s+eslint)(\s|$|;|\|)' 2>/dev/null; then
            OUTCOME="lint-fail"
        fi
    fi

    SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"
    CASCADE=false

    # --- Cascade detection ---
    # If the last 2 events were also failures on the same target, this is a cascade (3+ consecutive).
    if [ -f "$SESSION_FILE" ] && [ -n "$DETAIL" ]; then
        RECENT_FAILS=$(tail -2 "$SESSION_FILE" 2>/dev/null | jq -r 'select(.outcome == "failure" or .outcome == "test-fail" or .outcome == "lint-fail") | .detail // empty' 2>/dev/null) || RECENT_FAILS=""
        MATCH_COUNT=$(echo "$RECENT_FAILS" | grep -cxF "$DETAIL" 2>/dev/null) || MATCH_COUNT=0
        if [ "$MATCH_COUNT" -ge 2 ]; then
            CASCADE=true
        fi
    fi

    # --- Error categorization ---
    ERROR_CAT="unknown"
    case "${TOOL_NAME:-}" in
        Edit)
            ERROR_CAT="edit-mismatch"
            ;;
        Write)
            ERROR_CAT="write-fail"
            ;;
        Bash)
            if [ "$OUTCOME" = "test-fail" ]; then
                ERROR_CAT="test-fail"
            elif [ "$OUTCOME" = "lint-fail" ]; then
                ERROR_CAT="lint-fail"
            else
                ERROR_CAT="command-fail"
            fi
            ;;
        WebFetch|WebSearch)
            ERROR_CAT="network-fail"
            ;;
        *)
            ERROR_CAT="tool-fail"
            ;;
    esac

    jq -n -c \
        --argjson ts "${TS:-0}" \
        --arg tool "${TOOL_NAME:-unknown}" \
        --arg outcome "$OUTCOME" \
        --arg detail "${DETAIL:-unknown}" \
        --arg error_cat "$ERROR_CAT" \
        --argjson cascade "$CASCADE" \
        --argjson duration_ms "${DURATION_MS:-0}" \
        '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail, error_cat: $error_cat, cascade: $cascade, duration_ms: $duration_ms}' >> "$SESSION_FILE" 2>/dev/null || true

    # --- Cross-session error recurrence tracking (t-679) ---
    # Signature = hash of (tool_name + error_cat + first 80 chars of detail).
    # Counter stored in persistent JSONL; ruflo notified on escalation threshold (3+).
    RECURRENCE_FILE="$HOME/.claude/logs/error-recurrence.jsonl"
    mkdir -p "$HOME/.claude/logs" 2>/dev/null || true

    # Build signature: tool + category + normalized first token of detail
    SIG_DETAIL=$(echo "$DETAIL" | head -1 | cut -c1-80 | tr -d '\n' 2>/dev/null) || SIG_DETAIL=""
    SIG_INPUT="${TOOL_NAME}:${ERROR_CAT}:${SIG_DETAIL}"
    SIG_HASH=$(echo -n "$SIG_INPUT" | md5sum 2>/dev/null | cut -c1-16) || SIG_HASH=""

    if [ -n "$SIG_HASH" ]; then
        # Read current count for this hash (last occurrence wins)
        PREV_COUNT=0
        if [ -f "$RECURRENCE_FILE" ]; then
            PREV_COUNT=$(grep "\"hash\":\"$SIG_HASH\"" "$RECURRENCE_FILE" 2>/dev/null | tail -1 | jq -r '.count // 0' 2>/dev/null) || PREV_COUNT=0
        fi
        NEW_COUNT=$((PREV_COUNT + 1))

        # Append updated entry (readers use tail -1 per hash for latest)
        jq -n -c \
            --arg hash "$SIG_HASH" \
            --argjson count "$NEW_COUNT" \
            --argjson ts "${TS:-0}" \
            --arg tool "${TOOL_NAME:-unknown}" \
            --arg error_cat "$ERROR_CAT" \
            --arg detail "${SIG_DETAIL}" \
            --arg session "$SESSION_ID" \
            '{hash: $hash, count: $count, ts: $ts, tool: $tool, error_cat: $error_cat, detail: $detail, session: $session}' >> "$RECURRENCE_FILE" 2>/dev/null || true

        # On threshold (count == 3): store to ruflo as rule candidate (background, fire-and-forget)
        # Skip on low effort — ruflo escalation is non-critical and adds latency.
        if [ "$NEW_COUNT" -eq 3 ] && [ "${EFFORT_LEVEL:-normal}" != "low" ]; then
            SCRIPT_DIR_F="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            (
                if [ -f "$SCRIPT_DIR_F/lib/cf-env.sh" ]; then
                    source "$SCRIPT_DIR_F/lib/cf-env.sh"
                else
                    source "$HOME/.claude/scripts/cf-env.sh" 2>/dev/null || true
                fi
                if [ -n "${CF:-}" ]; then
                    STORE_VAL=$(jq -n -c \
                        --arg tool "${TOOL_NAME:-unknown}" \
                        --arg error_cat "$ERROR_CAT" \
                        --arg detail "$SIG_DETAIL" \
                        --argjson count "$NEW_COUNT" \
                        '{tool: $tool, error_cat: $error_cat, detail: $detail, count: $count, escalation: "rule-candidate"}')
                    cd "$HOME" && timeout 5 $CF memory store \
                        --key "error-recurrence:$SIG_HASH" \
                        --namespace pattern \
                        --tags "type:error-recurrence,escalate:rule-candidate" \
                        --value "$STORE_VAL" 2>/dev/null || true
                fi
            ) &
            disown 2>/dev/null || true
        fi
    fi

    # --- Cascade flag for PreToolUse throttle ---
    # When cascade detected on file-targeted tools, write a flag file so pre-tool-use.sh can nudge.
    # Flag is per-session + per-file to avoid cross-contamination.
    # Only for Edit/Write — Bash commands aren't file-targeted, so flags would be orphaned.
    if [ "$CASCADE" = true ] && [ -n "$DETAIL" ]; then
        case "${TOOL_NAME:-}" in
            Edit|Write)
                CASCADE_DIR="/tmp/brana-cascade"
                mkdir -p "$CASCADE_DIR" 2>/dev/null || true
                PATH_HASH=$(echo -n "$DETAIL" | md5sum 2>/dev/null | cut -c1-12) || PATH_HASH=$(echo "$DETAIL" | tr '/' '-' | sed 's/^-//')
                echo "$DETAIL" > "$CASCADE_DIR/${SESSION_ID}-${PATH_HASH}" 2>/dev/null || true
                ;;
        esac
    fi
fi

echo '{"continue": true}'
