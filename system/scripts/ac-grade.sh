#!/usr/bin/env bash
# ac-grade.sh — standalone, read-only execution of the AC-grammar heuristics.
#
# ADR-081 D1 (t-2869): the per-criterion CHECK-EXECUTION logic (distinct from
# ac-lint.sh's shape-only classifier), extracted so a standalone caller
# (`ac approve`, `stacked-verdict`) and the Stop-hook (goal-completion.sh, via
# t-2870) share ONE execution path instead of two independently-drifting ones.
#
# Usage:   ac-grade.sh <task-id> [--json] [--cwd <path>]
# Output:  JSON {"task_id":..., "graded":[{"criterion":..., "verdict":"pass|fail|unknown"}],
#                "counts":{"pass":N,"fail":N,"unknown":N}}
#          (--json is accepted for interface symmetry with future non-JSON output;
#          JSON is the only implemented mode today — every caller wants it)
#
# Never mutates any task field (gauge law) — reads acceptance_criteria once via
# `brana backlog get`, never calls `brana backlog set`.
#
# Working-directory resolution (ADR-081 D1, round-2 verification finding):
#   --cwd <path>   — trust the caller's binding directly (e.g. the Stop-hook,
#                    which already has active-goal.json's cwd).
#   (no --cwd)     — resolve from the task's own `branch` field via
#                    `git worktree list --porcelain`. Errors loudly — never
#                    silently falls back to the caller's current directory —
#                    if the branch is unrecorded or no worktree matches it.
#                    This repo runs concurrent per-task worktrees by hard rule;
#                    a silent-cwd default would let a human grade the wrong tree.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/cmd-allowlist.sh
source "${SCRIPT_DIR}/lib/cmd-allowlist.sh"
# shellcheck source=../hooks/lib/resolve-brana.sh
source "${SCRIPT_DIR}/../hooks/lib/resolve-brana.sh" 2>/dev/null || true

err() { echo "ac-grade.sh: $*" >&2; exit 1; }

[ ! -x "${BRANA:-}" ] && err "brana CLI not found (checked PLUGIN_DATA, dev target, PLUGIN_ROOT, PATH)"

TASK_ID="${1:-}"
[ -z "$TASK_ID" ] && err "usage: ac-grade.sh <task-id> [--json] [--cwd <path>]"
shift || true

CWD_OVERRIDE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --json) shift ;;   # only mode implemented — accepted, no-op
        --cwd) CWD_OVERRIDE="${2:-}"; shift 2 ;;
        *) err "unknown argument: $1" ;;
    esac
done

# ── Resolve WORK_DIR ───────────────────────────────────────────────────────
if [ -n "$CWD_OVERRIDE" ]; then
    [ -d "$CWD_OVERRIDE" ] || err "--cwd path does not exist: $CWD_OVERRIDE"
    WORK_DIR="$CWD_OVERRIDE"
else
    BRANCH=$("$BRANA" backlog get "$TASK_ID" --field branch 2>/dev/null | jq -r '. // empty' 2>/dev/null) || BRANCH=""
    [ -z "$BRANCH" ] && err "no branch recorded for $TASK_ID — cannot resolve a worktree, and this script never defaults to the caller's cwd"

    WT_LIST=$(git worktree list --porcelain 2>/dev/null) || err "git worktree list failed"
    MATCHES=$(awk -v want="refs/heads/${BRANCH}" '
        /^worktree / { p = substr($0, 10) }
        /^branch /   { if (substr($0, 8) == want) print p }
    ' <<<"$WT_LIST")
    MATCH_COUNT=$(grep -c . <<<"$MATCHES" 2>/dev/null || echo 0)

    [ "$MATCH_COUNT" -eq 0 ] && err "no worktree found for branch '$BRANCH' (task $TASK_ID) — the worktree may have been removed after merge; never grading against the caller's cwd instead"
    [ "$MATCH_COUNT" -gt 1 ] && err "ambiguous: $MATCH_COUNT worktrees match branch '$BRANCH' (task $TASK_ID) — refusing to guess, pass --cwd explicitly"

    WORK_DIR="$MATCHES"
fi
[ -d "$WORK_DIR" ] || err "resolved WORK_DIR does not exist: $WORK_DIR"

# ── Load acceptance_criteria ───────────────────────────────────────────────
CRITERIA_JSON=$("$BRANA" backlog get "$TASK_ID" --field acceptance_criteria 2>/dev/null) || CRITERIA_JSON="null"
CRITERIA_JSON=$(jq -c '. // []' <<<"$CRITERIA_JSON" 2>/dev/null) || CRITERIA_JSON="[]"
CRITERIA_COUNT=$(jq 'length' <<<"$CRITERIA_JSON" 2>/dev/null) || CRITERIA_COUNT=0

PASSED=0
FAILED=0
UNKNOWN=0
GRADED=()

emit() {   # emit <criterion> <verdict>
    GRADED+=("$(jq -n --arg c "$1" --arg v "$2" '{criterion:$c, verdict:$v}')")
}

if [ "$CRITERIA_COUNT" -gt 0 ]; then
for i in $(seq 0 $((CRITERIA_COUNT - 1))); do
    criterion=$(jq -r ".[$i]" <<<"$CRITERIA_JSON" 2>/dev/null) || criterion=""
    [ -z "$criterion" ] && continue

    criterion="${criterion#AC: }"
    criterion="${criterion#AC:}"
    criterion="${criterion# }"

    # ── H1: file exists ────────────────────────────────────────────────────
    if grep -qiE "exists$|^file .+ exists" <<<"$criterion"; then
        path=$(grep -oE '[a-zA-Z0-9_./-]+\.(sh|md|json|rs|py|ts|js|toml)' <<<"$criterion" | head -1)
        if [ -n "$path" ]; then
            if test -f "${WORK_DIR}/${path}" 2>/dev/null; then
                PASSED=$((PASSED + 1)); emit "$criterion" "pass"
            else
                FAILED=$((FAILED + 1)); emit "$criterion" "fail"
            fi
            continue
        fi
    fi

    # ── H2: brana backlog get ... returns ... ──────────────────────────────
    if grep -qiE "^brana backlog get .+ returns" <<<"$criterion"; then
        cmd_part=$(sed 's/ returns.*//' <<<"$criterion")
        expected=$(grep -oE 'returns .+' <<<"$criterion" | sed 's/^returns //')
        cli_args=$(sed 's/^brana //' <<<"$cmd_part")
        result=$(cd "$WORK_DIR" && "$BRANA" $cli_args 2>/dev/null) || result=""
        if [ -n "$result" ] && grep -qF "$expected" <<<"$result" 2>/dev/null; then
            PASSED=$((PASSED + 1)); emit "$criterion" "pass"
        else
            FAILED=$((FAILED + 1)); emit "$criterion" "fail"
        fi
        continue
    fi

    # ── H3: validate.sh Check N passes ─────────────────────────────────────
    if grep -qiE "validate\.sh.*check [0-9]+" <<<"$criterion"; then
        check_n=$(grep -oE '[Cc]heck [0-9]+' <<<"$criterion" | awk '{print $2}')
        if [ -f "$WORK_DIR/validate.sh" ] && [ -n "$check_n" ]; then
            if (cd "$WORK_DIR" && ./validate.sh --check "$check_n" >/dev/null 2>&1); then
                PASSED=$((PASSED + 1)); emit "$criterion" "pass"
            else
                FAILED=$((FAILED + 1)); emit "$criterion" "fail"
            fi
        else
            UNKNOWN=$((UNKNOWN + 1)); emit "$criterion" "unknown"
        fi
        continue
    fi

    # ── H4: hook {name}.sh exists ──────────────────────────────────────────
    if grep -qiE "hook .+\.sh exists" <<<"$criterion"; then
        hook_name=$(grep -oE '[a-zA-Z0-9_-]+\.sh' <<<"$criterion" | head -1)
        if [ -n "$hook_name" ] && test -f "$WORK_DIR/system/hooks/$hook_name" 2>/dev/null; then
            PASSED=$((PASSED + 1)); emit "$criterion" "pass"
        else
            FAILED=$((FAILED + 1)); emit "$criterion" "fail"
        fi
        continue
    fi

    # ── H5: file {path} contains "{string}" ────────────────────────────────
    if grep -qiE '^file .+ contains "' <<<"$criterion"; then
        path=$(grep -oE 'file [^ ]+' <<<"$criterion" | awk '{print $2}')
        search=$(grep -oE '"[^"]+"' <<<"$criterion" | head -1 | tr -d '"')
        if [ -n "$path" ] && [ -n "$search" ] && ! grep -qE '^/|\.\.' <<<"$path"; then
            target="${WORK_DIR}/${path}"
            if [ -f "$target" ] && grep -qF "$search" "$target" 2>/dev/null; then
                PASSED=$((PASSED + 1)); emit "$criterion" "pass"
            else
                FAILED=$((FAILED + 1)); emit "$criterion" "fail"
            fi
        else
            UNKNOWN=$((UNKNOWN + 1)); emit "$criterion" "unknown"
        fi
        continue
    fi

    # ── H6: jq '{expr}' {file} returns "{value}" ───────────────────────────
    if grep -qiE "^jq '.+' .+ returns" <<<"$criterion"; then
        expr=$(grep -oE "'[^']+'" <<<"$criterion" | head -1 | tr -d "'")
        file=$(sed "s/jq '[^']*' //" <<<"$criterion" | grep -oE '[^ ]+' | head -1)
        expected=$(grep -oE 'returns "[^"]+"' <<<"$criterion" | grep -oE '"[^"]+"' | head -1 | tr -d '"')
        if [ -n "$expr" ] && [ -n "$file" ] && [ -n "$expected" ] && ! grep -qE '^/|\.\.' <<<"$file"; then
            target="${WORK_DIR}/${file}"
            result=$(jq -r "$expr" "$target" 2>/dev/null) || { UNKNOWN=$((UNKNOWN + 1)); emit "$criterion" "unknown"; continue; }
            if [ "$result" = "$expected" ]; then
                PASSED=$((PASSED + 1)); emit "$criterion" "pass"
            else
                FAILED=$((FAILED + 1)); emit "$criterion" "fail"
            fi
        else
            UNKNOWN=$((UNKNOWN + 1)); emit "$criterion" "unknown"
        fi
        continue
    fi

    # ── H7: "{command}" passes ──────────────────────────────────────────────
    if grep -qiE '^"[^"]+" passes$' <<<"$criterion"; then
        cmd=$(grep -oE '"[^"]+"' <<<"$criterion" | head -1 | tr -d '"')
        if allowlisted_command "$cmd"; then
            if (cd "$WORK_DIR" && eval "$cmd" >/dev/null 2>&1); then
                PASSED=$((PASSED + 1)); emit "$criterion" "pass"
            else
                FAILED=$((FAILED + 1)); emit "$criterion" "fail"
            fi
        else
            UNKNOWN=$((UNKNOWN + 1)); emit "$criterion" "unknown"
        fi
        continue
    fi

    # ── H8: git log checks ──────────────────────────────────────────────────
    if grep -qiE "^changes to .+ committed$" <<<"$criterion"; then
        file=$(sed -e 's/^[Cc]hanges to //' -e 's/ [Cc]ommitted$//' <<<"$criterion")
        result=$(cd "$WORK_DIR" && git log --oneline -- "$file" 2>/dev/null | head -1) || result=""
        if [ -n "$result" ]; then PASSED=$((PASSED + 1)); emit "$criterion" "pass"
        else FAILED=$((FAILED + 1)); emit "$criterion" "fail"; fi
        continue
    fi
    if grep -qiE '^commit message contains "' <<<"$criterion"; then
        search=$(grep -oE '"[^"]+"' <<<"$criterion" | head -1 | tr -d '"')
        result=$(cd "$WORK_DIR" && git log --oneline --grep="$search" 2>/dev/null | head -1) || result=""
        if [ -n "$result" ]; then PASSED=$((PASSED + 1)); emit "$criterion" "pass"
        else FAILED=$((FAILED + 1)); emit "$criterion" "fail"; fi
        continue
    fi

    # ── H9: validate.sh passes (full run) ──────────────────────────────────
    if grep -qiE 'validate\.sh' <<<"$criterion" \
       && grep -qiE '(passes|exit 0|exit code 0)' <<<"$criterion" \
       && ! grep -qiE 'check [0-9]' <<<"$criterion"; then
        if [ -f "$WORK_DIR/validate.sh" ]; then
            if (cd "$WORK_DIR" && ./validate.sh >/dev/null 2>&1); then
                PASSED=$((PASSED + 1)); emit "$criterion" "pass"
            else
                FAILED=$((FAILED + 1)); emit "$criterion" "fail"
            fi
        else
            UNKNOWN=$((UNKNOWN + 1)); emit "$criterion" "unknown"
        fi
        continue
    fi

    # ── H10: demoable: <command> ───────────────────────────────────────────
    if grep -qiE '^demoable: .+' <<<"$criterion"; then
        cmd=$(sed 's/^[Dd]emoable: *//' <<<"$criterion")
        if allowlisted_command "$cmd"; then
            if (cd "$WORK_DIR" && eval "$cmd" >/dev/null 2>&1); then
                PASSED=$((PASSED + 1)); emit "$criterion" "pass"
            else
                FAILED=$((FAILED + 1)); emit "$criterion" "fail"
            fi
        else
            UNKNOWN=$((UNKNOWN + 1)); emit "$criterion" "unknown"
        fi
        continue
    fi

    # ── Fallback: unknown pattern ───────────────────────────────────────────
    UNKNOWN=$((UNKNOWN + 1)); emit "$criterion" "unknown"
done
fi

if [ "${#GRADED[@]}" -eq 0 ]; then
    GRADED_JSON="[]"
else
    GRADED_JSON=$(printf '%s\n' "${GRADED[@]}" | jq -s .)
fi

jq -n \
    --arg task_id "$TASK_ID" \
    --argjson graded "$GRADED_JSON" \
    --argjson pass "$PASSED" \
    --argjson fail "$FAILED" \
    --argjson unknown "$UNKNOWN" \
    '{task_id: $task_id, graded: $graded, counts: {pass: $pass, fail: $fail, unknown: $unknown}}'
