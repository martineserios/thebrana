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

# Stale guard — goal files older than 48h are from abandoned/crashed sessions
[ $(( $(date +%s) - $(stat -c '%Y' "$GOAL_FILE" 2>/dev/null || echo 0) )) -gt 172800 ] && { rm -f "$GOAL_FILE"; echo '{"continue": true}'; exit 0; }
# Session binding — only fire for the session that set this goal
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null) || SESSION_ID=""
GOAL_SESSION=$(jq -r '.session_id // ""' "$GOAL_FILE" 2>/dev/null) || GOAL_SESSION=""
[ -n "$GOAL_SESSION" ] && [ -n "$SESSION_ID" ] && [ "$SESSION_ID" != "$GOAL_SESSION" ] && { echo '{"continue": true}'; exit 0; }

TASK_ID=$(jq -r '.task_id // ""' "$GOAL_FILE" 2>/dev/null) || TASK_ID=""
GOAL_CWD=$(jq -r '.cwd // ""' "$GOAL_FILE" 2>/dev/null) || GOAL_CWD=""
CRITERIA_JSON=$(jq -r '.criteria // []' "$GOAL_FILE" 2>/dev/null) || CRITERIA_JSON="[]"

[ -z "$TASK_ID" ] && { echo '{"continue": true}'; exit 0; }

# Only fire for the repo that started the goal — exit if CWD unknown or mismatched
[ -z "$GOAL_CWD" ] && { echo '{"continue": true}'; exit 0; }
[ -n "$CWD" ] && [ "$CWD" != "$GOAL_CWD" ] && { echo '{"continue": true}'; exit 0; }

WORK_DIR="${GOAL_CWD:-$CWD}"

# Locate brana CLI
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/resolve-brana.sh
source "${SCRIPT_DIR}/lib/resolve-brana.sh" 2>/dev/null || true
[ ! -x "${BRANA:-}" ] && { echo '{"continue": true}'; exit 0; }

CRITERIA_COUNT=$(echo "$CRITERIA_JSON" | jq 'length' 2>/dev/null) || CRITERIA_COUNT=0
[ "$CRITERIA_COUNT" -eq 0 ] && { echo '{"continue": true}'; exit 0; }

# Validate each criterion using deterministic heuristics (ADR-047 §3).
# Canonical grammar (the 8 patterns below): docs/architecture/ac-grammar.md —
# edit that file first when adding/changing a heuristic so plan-lint stays in sync (t-2199).
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

    # ── Heuristic 5: file {path} contains "{string}" ──────────────────────────
    if echo "$criterion" | grep -qiE '^file .+ contains "'; then
        path=$(echo "$criterion" | grep -oE 'file [^ ]+' | awk '{print $2}')
        search=$(echo "$criterion" | grep -oE '"[^"]+"' | head -1 | tr -d '"')
        # Sandbox: reject absolute paths and path traversal
        if [ -n "$path" ] && [ -n "$search" ] && \
           ! echo "$path" | grep -qE '^/|\.\.' ; then
            target="${WORK_DIR}/${path}"
            if [ -f "$target" ] && grep -qF "$search" "$target" 2>/dev/null; then
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

    # ── Heuristic 6: jq '{expr}' {file} returns "{value}" ────────────────────
    if echo "$criterion" | grep -qiE "^jq '.+' .+ returns"; then
        expr=$(echo "$criterion" | grep -oE "'[^']+'" | head -1 | tr -d "'")
        file=$(echo "$criterion" | sed "s/jq '[^']*' //" | grep -oE '[^ ]+' | head -1)
        expected=$(echo "$criterion" | grep -oE 'returns "[^"]+"' | grep -oE '"[^"]+"' | head -1 | tr -d '"')
        # Sandbox: reject absolute paths and path traversal
        if [ -n "$expr" ] && [ -n "$file" ] && [ -n "$expected" ] && \
           ! echo "$file" | grep -qE '^/|\.\.' ; then
            target="${WORK_DIR}/${file}"
            result=$(jq -r "$expr" "$target" 2>/dev/null) || { UNKNOWN=$((UNKNOWN + 1)); UNKNOWN_LIST="$UNKNOWN_LIST\n  ? $criterion"; continue; }
            if [ "$result" = "$expected" ]; then
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

    # ── Heuristic 7: "{command}" passes ──────────────────────────────────────
    if echo "$criterion" | grep -qiE '^"[^"]+" passes$'; then
        cmd=$(echo "$criterion" | grep -oE '"[^"]+"' | head -1 | tr -d '"')
        # Allowlist: only execute known-safe test commands
        if echo "$cmd" | grep -qE '^(cargo test|pytest|python -m pytest|bun test|npm test|yarn test|bash tests/|\./tests/)'; then
            if (cd "$WORK_DIR" && eval "$cmd" >/dev/null 2>&1); then
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

    # ── Heuristic 8: git log check ────────────────────────────────────────────
    if echo "$criterion" | grep -qiE "^changes to .+ committed$"; then
        file=$(echo "$criterion" | sed 's/^[Cc]hanges to //' | sed 's/ [Cc]ommitted$//')
        result=$(cd "$WORK_DIR" && git log --oneline -- "$file" 2>/dev/null | head -1) || result=""
        if [ -n "$result" ]; then
            PASSED=$((PASSED + 1))
        else
            FAILED=$((FAILED + 1))
            FAILED_LIST="$FAILED_LIST\n  ✗ $criterion"
        fi
        continue
    fi
    if echo "$criterion" | grep -qiE '^commit message contains "'; then
        search=$(echo "$criterion" | grep -oE '"[^"]+"' | head -1 | tr -d '"')
        result=$(cd "$WORK_DIR" && git log --oneline --grep="$search" 2>/dev/null | head -1) || result=""
        if [ -n "$result" ]; then
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

# Structured audit (t-2218, AC #4): forensic trail of which criterion got which verdict,
# plus registered_as_red per declared test (always false in Stage 2 — red-verification is
# t-2216, blocking Stage 3). One JSONL record per criterion + per registered test.
AUDIT_FILE="$HOME/.claude/run-state/${TASK_ID}-audit.jsonl"
mkdir -p "$HOME/.claude/run-state" 2>/dev/null || true
audit_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || audit_ts=""
for ai in $(seq 0 $((CRITERIA_COUNT - 1))); do
    ac=$(echo "$CRITERIA_JSON" | jq -r ".[$ai]" 2>/dev/null); [ -z "$ac" ] && continue
    if printf '%b' "$FAILED_LIST" | grep -qF "$ac"; then av="fail"
    elif printf '%b' "$UNKNOWN_LIST" | grep -qF "$ac"; then av="unknown"
    else av="pass"; fi
    printf '{"ts":"%s","task_id":"%s","criterion":%s,"verdict":"%s"}\n' \
        "$audit_ts" "$TASK_ID" "$(printf '%s' "$ac" | jq -R . 2>/dev/null)" "$av" >> "$AUDIT_FILE" 2>/dev/null || true
done
jq -r '.tests_required // [] | .[]' "$GOAL_FILE" 2>/dev/null | while IFS= read -r at; do
    [ -z "$at" ] && continue
    printf '{"ts":"%s","task_id":"%s","registered_test":%s,"registered_as_red":false}\n' \
        "$audit_ts" "$TASK_ID" "$(printf '%s' "$at" | jq -R . 2>/dev/null)" >> "$AUDIT_FILE" 2>/dev/null || true
done

if [ "$FAILED" -eq 0 ] && [ "$UNKNOWN" -eq 0 ] && [ "$PASSED" -gt 0 ]; then
    # All criteria green — but `/goal` is an optimizer over the done-signal, so the
    # grader must live outside the agent's control (ADR-061 §4 invariants 1+2;
    # tests: tests/test-goal-completion.sh G1-G6). Refuse auto-advance unless:
    #   (1) PRESENCE INTERLOCK — a fresh (<15m) presence token proves an
    #       interactive session for this Stop event's session_id, and
    #   (2) GRADER IMMUTABILITY — base_ref is pinned and nothing the grader reads
    #       changed since it (*.test.*, tests/**, __mocks__/**, .claude/tasks.json),
    #       checked as a tracked diff vs base_ref AND as untracked files.
    GATE_REASON=""

    PRESENCE_TOK="$HOME/.claude/run-state/presence-${SESSION_ID}"
    if [ -z "$SESSION_ID" ] || [ ! -f "$PRESENCE_TOK" ] || \
       [ -n "$(find "$PRESENCE_TOK" -mmin +15 2>/dev/null)" ]; then
        GATE_REASON="no verified interactive session (presence interlock)"
    fi

    if [ -z "$GATE_REASON" ]; then
        BASE_REF=$(jq -r '.base_ref // ""' "$GOAL_FILE" 2>/dev/null) || BASE_REF=""
        if [ -z "$BASE_REF" ]; then
            GATE_REASON="goal has no pinned base-ref — cannot verify grader integrity"
        else
            GRADER_RE='(\.test\.|(^|/)tests/|(^|/)__mocks__/|(^|/)\.claude/tasks\.json$)'
            # Option C (t-2205, ADR-061 §4 invariant-2 refinement): TDD writes the test
            # file DURING the span, so a single base_ref pin must distinguish Modified
            # (pre-existing grader paths — always the gaming surface) from Added (new files
            # — exempt IFF the build registered them in active-goal.json.tests_required[]).
            TESTS_REQ=$(jq -r '.tests_required // [] | .[]' "$GOAL_FILE" 2>/dev/null) || TESTS_REQ=""
            # Channel 1a — MODIFIED pre-existing grader paths: always blocked.
            MODIFIED=$(git -C "$WORK_DIR" diff --name-only --diff-filter=M "$BASE_REF" 2>/dev/null | grep -E "$GRADER_RE")
            # Channel 1b + 2 — ADDED (committed) and untracked new grader paths: blocked
            # unless registered as a declared TDD test.
            UNREG=""
            while IFS= read -r f; do
                [ -z "$f" ] && continue
                printf '%s\n' "$TESTS_REQ" | grep -qxF "$f" || UNREG="$UNREG $f"
            done <<EOF
$(
    { git -C "$WORK_DIR" diff --name-only --diff-filter=A "$BASE_REF" 2>/dev/null
      git -C "$WORK_DIR" ls-files --others --exclude-standard 2>/dev/null
    } | grep -E "$GRADER_RE"
)
EOF
            CHANGED=$(printf '%s %s' "$MODIFIED" "$UNREG" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//' | cut -c1-200)
            [ -n "$CHANGED" ] && GATE_REASON="grader path changed since goal start ($CHANGED)"
        fi
    fi

    if [ -n "$GATE_REASON" ]; then
        # Gate: do NOT auto-complete, do NOT remove the goal file. Surface for review.
        MSG="goal blocked: $GATE_REASON — $PASSED/$TOTAL criteria green but $TASK_ID left in_progress. Run /brana:backlog done $TASK_ID after manual review."
    else
        # Interlocks satisfied — auto-complete the task
        (cd "$WORK_DIR" && "$BRANA" backlog set "$TASK_ID" status completed 2>/dev/null) || true
        (cd "$WORK_DIR" && "$BRANA" backlog set "$TASK_ID" completed "$(date +%Y-%m-%d)" 2>/dev/null) || true
        rm -f "$GOAL_FILE" 2>/dev/null || true
        MSG="Goal complete: all $PASSED/$TOTAL criteria passed. $TASK_ID auto-marked completed."
    fi
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
