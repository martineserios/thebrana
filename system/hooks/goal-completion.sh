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

# Validate each criterion via ac-grade.sh (t-2870, ADR-081 D1) — the shared,
# standalone heuristic-execution script (t-2869). Canonical grammar (10
# patterns): docs/architecture/ac-grammar.md — edit that file first when
# adding/changing a heuristic, then ac-grade.sh (the sole execution point).
#
# This hook supplies its own frozen criteria snapshot via --criteria-json
# (never lets ac-grade.sh re-derive live from tasks.json — a task's
# acceptance_criteria can change mid-build, and grading against the live
# value would silently defeat the grader-immutability contract this hook
# exists to enforce) and its own trusted WORK_DIR via --cwd (skips
# ac-grade.sh's worktree auto-resolution — this hook already has a verified
# binding from active-goal.json).
GRADE_JSON=$("${SCRIPT_DIR}/../scripts/ac-grade.sh" "$TASK_ID" --json --cwd "$WORK_DIR" --criteria-json "$CRITERIA_JSON" 2>/dev/null) \
    || { echo '{"continue": true}'; exit 0; }

PASSED=$(jq -r '.counts.pass // 0' <<<"$GRADE_JSON" 2>/dev/null) || PASSED=0
FAILED=$(jq -r '.counts.fail // 0' <<<"$GRADE_JSON" 2>/dev/null) || FAILED=0
UNKNOWN=$(jq -r '.counts.unknown // 0' <<<"$GRADE_JSON" 2>/dev/null) || UNKNOWN=0
FAILED_LIST=$(jq -r '[.graded[]? | select(.verdict=="fail") | "  ✗ " + .criterion] | join("\n")' <<<"$GRADE_JSON" 2>/dev/null) || FAILED_LIST=""
UNKNOWN_LIST=$(jq -r '[.graded[]? | select(.verdict=="unknown") | "  ? " + .criterion] | join("\n")' <<<"$GRADE_JSON" 2>/dev/null) || UNKNOWN_LIST=""
[ -n "$FAILED_LIST" ] && FAILED_LIST=$'\n'"$FAILED_LIST"
[ -n "$UNKNOWN_LIST" ] && UNKNOWN_LIST=$'\n'"$UNKNOWN_LIST"

TOTAL=$((PASSED + FAILED + UNKNOWN))
MSG=""

# Structured audit (t-2218, AC #4): forensic trail of which criterion got which verdict,
# plus registered_as_red per declared test — true by construction since t-2216:
# red-verification.sh is the sole writer of tests_required[] and registers a path only
# when its staged blob ran red. One JSONL record per criterion + per registered test.
# (t-2870: built directly from ac-grade.sh's graded[] array — no more grep -F
# matching a criterion against reconstructed FAILED_LIST/UNKNOWN_LIST strings,
# which was the original loop's own fragile indirection.)
AUDIT_FILE="$HOME/.claude/run-state/${TASK_ID}-audit.jsonl"
mkdir -p "$HOME/.claude/run-state" 2>/dev/null || true
audit_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || audit_ts=""
jq -c '.graded[]? // empty' <<<"$GRADE_JSON" 2>/dev/null | while IFS= read -r entry; do
    ac=$(jq -r '.criterion' <<<"$entry" 2>/dev/null)
    av=$(jq -r '.verdict' <<<"$entry" 2>/dev/null)
    [ -z "$ac" ] && continue
    printf '{"ts":"%s","task_id":"%s","criterion":%s,"verdict":"%s"}\n' \
        "$audit_ts" "$TASK_ID" "$(printf '%s' "$ac" | jq -R . 2>/dev/null)" "$av" >> "$AUDIT_FILE" 2>/dev/null || true
done
jq -r '.tests_required // [] | .[]' "$GOAL_FILE" 2>/dev/null | while IFS= read -r at; do
    [ -z "$at" ] && continue
    printf '{"ts":"%s","task_id":"%s","registered_test":%s,"registered_as_red":true}\n' \
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
            # Channel 3 (ADR-082 §5) — registered-test content re-verification.
            # A path in tests_required[] is exempt from channels 1b/2 forever, and
            # "Added" never becomes "Modified" vs base_ref — so without this check a
            # registered test could be weakened after its red registration undetected.
            # red-verification.sh pins tests_hashes{path: sha256-of-staged-blob} at
            # registration (re-pinning when a changed blob is re-proven red). The walk
            # is over tests_required[] — the authoritative list — so a registered path
            # with NO hash entry gates too (fail-closed; panel repair: iterating
            # tests_hashes alone silently kept the pre-ADR-082 exemption). An
            # unreadable tests_hashes map also gates rather than passing silently.
            if [ -z "$GATE_REASON" ]; then
                HASH_MISMATCH=""
                HASHES_JSON=$(jq -c '.tests_hashes // {}' "$GOAL_FILE" 2>/dev/null) || HASHES_JSON=""
                if [ -z "$HASHES_JSON" ]; then
                    [ -n "$TESTS_REQ" ] && GATE_REASON="registered tests present but tests_hashes unreadable — cannot verify grader integrity"
                else
                    while IFS= read -r hp; do
                        [ -z "$hp" ] && continue
                        hh=$(jq -r --arg p "$hp" '.[$p] // ""' <<<"$HASHES_JSON" 2>/dev/null) || hh=""
                        if [ -z "$hh" ]; then
                            HASH_MISMATCH="$HASH_MISMATCH $hp(unpinned)"
                            continue
                        fi
                        cur=$(sha256sum "$WORK_DIR/$hp" 2>/dev/null | cut -d' ' -f1) || cur=""
                        [ "$cur" != "$hh" ] && HASH_MISMATCH="$HASH_MISMATCH $hp"
                    done <<EOF
$TESTS_REQ
EOF
                    if [ -n "$HASH_MISMATCH" ]; then
                        GATE_REASON="registered test content changed or unpinned since red registration (hash mismatch:$(printf '%s' "$HASH_MISMATCH" | cut -c1-160))"
                    fi
                fi
            fi
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
