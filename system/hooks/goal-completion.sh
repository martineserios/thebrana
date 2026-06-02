#!/usr/bin/env bash
# Brana Stop hook — validate /goal criteria and auto-complete task.
# Fires on every clean Stop event. Fire-and-forget; exit codes ignored by CC.
# Input:  stdin JSON (session_id, transcript_path, cwd)
# Output: {"continue": true, "additionalContext": "..."} or {"continue": true}

cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null) || CWD=""

GOAL_FILE="$HOME/.claude/run-state/active-goal.json"
[ ! -f "$GOAL_FILE" ] && { echo '{"continue": true}'; exit 0; }

TASK_ID=$(jq -r '.task_id // ""' "$GOAL_FILE" 2>/dev/null) || TASK_ID=""
GOAL_CWD=$(jq -r '.cwd // ""' "$GOAL_FILE" 2>/dev/null) || GOAL_CWD=""
CRITERIA_JSON=$(jq -r '.criteria // []' "$GOAL_FILE" 2>/dev/null) || CRITERIA_JSON="[]"

[ -z "$TASK_ID" ] && { echo '{"continue": true}'; exit 0; }

# Only fire for the repo that started the goal
[ -n "$GOAL_CWD" ] && [ -n "$CWD" ] && [ "$CWD" != "$GOAL_CWD" ] && { echo '{"continue": true}'; exit 0; }

WORK_DIR="${GOAL_CWD:-$CWD}"

# Locate brana CLI
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/resolve-brana.sh
source "${SCRIPT_DIR}/lib/resolve-brana.sh" 2>/dev/null || true
[ ! -x "${BRANA:-}" ] && { echo '{"continue": true}'; exit 0; }

CRITERIA_COUNT=$(echo "$CRITERIA_JSON" | jq 'length' 2>/dev/null) || CRITERIA_COUNT=0
[ "$CRITERIA_COUNT" -eq 0 ] && { echo '{"continue": true}'; exit 0; }

# Validate each criterion using deterministic heuristics (ADR-047 §3)
PASSED=0
FAILED=0
UNKNOWN=0
FAILED_LIST=""
UNKNOWN_LIST=""

for i in $(seq 0 $((CRITERIA_COUNT - 1))); do
    criterion=$(echo "$CRITERIA_JSON" | jq -r ".[$i]" 2>/dev/null) || criterion=""
    [ -z "$criterion" ] && continue

    # Strip leading "AC: " prefix if present
    criterion="${criterion#AC: }"
    criterion="${criterion#AC:}"
    criterion="${criterion# }"

    # ── Heuristic 1: file exists ──────────────────────────────────────────────
    if echo "$criterion" | grep -qiE "exists$|^file .+ exists"; then
        path=$(echo "$criterion" | grep -oE '[a-zA-Z0-9_./-]+\.(sh|md|json|rs|py|ts|js|toml)' | head -1)
        if [ -n "$path" ]; then
            target="${WORK_DIR:+$WORK_DIR/}$path"
            if test -f "$target" 2>/dev/null; then
                PASSED=$((PASSED + 1))
            else
                FAILED=$((FAILED + 1))
                FAILED_LIST="$FAILED_LIST\n  ✗ $criterion"
            fi
            continue
        fi
    fi

    # ── Heuristic 2: brana backlog get ... returns ... ────────────────────────
    if echo "$criterion" | grep -qiE "^brana backlog get .+ returns"; then
        cmd_part=$(echo "$criterion" | sed 's/ returns.*//')
        expected=$(echo "$criterion" | grep -oE 'returns .+' | sed 's/^returns //')
        cli_args=$(echo "$cmd_part" | sed 's/^brana //')
        result=$(cd "$WORK_DIR" && "$BRANA" $cli_args 2>/dev/null) || result=""
        if [ -n "$result" ] && echo "$result" | grep -qF "$expected" 2>/dev/null; then
            PASSED=$((PASSED + 1))
        else
            FAILED=$((FAILED + 1))
            FAILED_LIST="$FAILED_LIST\n  ✗ $criterion"
        fi
        continue
    fi

    # ── Heuristic 3: validate.sh Check N passes ───────────────────────────────
    if echo "$criterion" | grep -qiE "validate\.sh.*check [0-9]+"; then
        check_n=$(echo "$criterion" | grep -oE '[Cc]heck [0-9]+' | awk '{print $2}')
        if [ -f "$WORK_DIR/validate.sh" ] && [ -n "$check_n" ]; then
            if (cd "$WORK_DIR" && ./validate.sh --check "$check_n" >/dev/null 2>&1); then
                PASSED=$((PASSED + 1))
            else
                FAILED=$((FAILED + 1))
                FAILED_LIST="$FAILED_LIST\n  ✗ $criterion"
            fi
        else
            UNKNOWN=$((UNKNOWN + 1))
            UNKNOWN_LIST="$UNKNOWN_LIST\n  ? $criterion"
        fi
        continue
    fi

    # ── Heuristic 4: hook {name}.sh exists in system/hooks/ ──────────────────
    if echo "$criterion" | grep -qiE "hook .+\.sh exists"; then
        hook_name=$(echo "$criterion" | grep -oE '[a-zA-Z0-9_-]+\.sh' | head -1)
        if [ -n "$hook_name" ] && test -f "$WORK_DIR/system/hooks/$hook_name" 2>/dev/null; then
            PASSED=$((PASSED + 1))
        else
            FAILED=$((FAILED + 1))
            FAILED_LIST="$FAILED_LIST\n  ✗ $criterion"
        fi
        continue
    fi

    # ── Fallback: unknown pattern — cannot auto-validate ─────────────────────
    UNKNOWN=$((UNKNOWN + 1))
    UNKNOWN_LIST="$UNKNOWN_LIST\n  ? $criterion"
done

TOTAL=$((PASSED + FAILED + UNKNOWN))
MSG=""

if [ "$FAILED" -eq 0 ] && [ "$UNKNOWN" -eq 0 ] && [ "$PASSED" -gt 0 ]; then
    # All criteria passed — auto-complete the task
    (cd "$WORK_DIR" && "$BRANA" backlog set "$TASK_ID" status completed 2>/dev/null) || true
    (cd "$WORK_DIR" && "$BRANA" backlog set "$TASK_ID" completed "$(date +%Y-%m-%d)" 2>/dev/null) || true
    rm -f "$GOAL_FILE" 2>/dev/null || true
    MSG="Goal complete: all $PASSED/$TOTAL criteria passed. $TASK_ID auto-marked completed."
elif [ "$FAILED" -gt 0 ]; then
    # Surface failures; leave task in_progress
    NOTE="goal exit: $PASSED/$TOTAL criteria passed — manual review needed. Failed:$(printf '%b' "$FAILED_LIST")"
    (cd "$WORK_DIR" && "$BRANA" backlog set "$TASK_ID" notes --append "$NOTE" 2>/dev/null) || true
    MSG="$TASK_ID: $PASSED/$TOTAL criteria passed. Failed:$(printf '%b' "$FAILED_LIST")  Run /brana:backlog done $TASK_ID after fixing."
elif [ "$UNKNOWN" -gt 0 ]; then
    # All unknown — surface for manual sign-off
    MSG="$TASK_ID: $UNKNOWN criteria need manual sign-off:$(printf '%b' "$UNKNOWN_LIST")  Run /brana:backlog done $TASK_ID to complete."
fi

if [ -n "$MSG" ]; then
    ESCAPED=$(printf '%s' "$MSG" | jq -Rs '.')
    echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
else
    echo '{"continue": true}'
fi
