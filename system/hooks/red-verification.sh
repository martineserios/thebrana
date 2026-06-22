#!/usr/bin/env bash
#
# red-verification.sh — pre-commit registration gate for /goal TDD (ADR-061 §4, t-2216).
#
# Closes the Stage-2 gap. The build loop used to register every new test path into
# active-goal.json.tests_required[] on trust, so a trivially-green test (or an injected
# fixture) could be registered and thereby exempt itself from goal-completion.sh's
# grader-immutability check — gaming the auto-complete grader. This hook makes the
# exemption EARNED: a newly-added staged test is registered ONLY if its staged blob runs
# RED (exit != 0), proving it is a real failing test rather than a green stub or a
# non-runnable file masquerading as one.
#
# Surface: invoked from the git pre-commit chain (system/scripts/git-hooks/pre-commit),
# so it reads the real staged index AFTER `git add`, for every committer — the grader
# lives outside the agent's control (ADR-061 §4 invariant 2). It grades the STAGED blob,
# not the working tree, so a stage-green / worktree-red swap cannot earn a false exemption.
#
# Fail-closed: anything not provably red (green, un-runnable fixture, unknown type,
# timeout, jq missing) is NOT registered. goal-completion.sh then blocks auto-complete
# ("Added test not in tests_required") and a human completes the task manually.
#
# This hook NEVER blocks the commit — registration is a side effect, so it always exits 0.

set -uo pipefail

GOAL_FILE="${BRANA_GOAL_FILE:-$HOME/.claude/run-state/active-goal.json}"

# No active /goal → nothing to register. jq is required to edit the goal file safely.
[ -f "$GOAL_FILE" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$ROOT" ] || exit 0

# Only act for the repo that owns this goal.
GOAL_CWD=$(jq -r '.cwd // ""' "$GOAL_FILE" 2>/dev/null) || GOAL_CWD=""
[ -n "$GOAL_CWD" ] && [ "$GOAL_CWD" != "$ROOT" ] && exit 0

# Grader test-path regex — mirrors goal-completion.sh GRADER_RE (test files only;
# .claude/tasks.json is never a newly-Added registration candidate).
GRADER_RE='(\.test\.|(^|/)tests/|(^|/)__mocks__/)'

# Newly-ADDED staged files matching the grader regex (Modified paths are always blocked
# by the grader, so they are never registration candidates).
mapfile -t ADDED < <(git -C "$ROOT" diff --cached --name-only --diff-filter=A 2>/dev/null \
    | grep -E "$GRADER_RE" || true)
[ "${#ADDED[@]}" -eq 0 ] && exit 0

# Run the staged blob of $1 (repo-relative). Returns 0 iff it ran RED (exit != 0 and not
# a timeout). Extracts the blob into the file's own directory under a temp name so the
# test's own relative `source ../foo` resolves exactly as it will once committed.
# Only `.sh` tests are runnable here (this repo's test suites are bash); any other type is
# fail-closed (not registered → grader blocks → human completes manually).
run_red() {
    local f="$1" dir base tmp rc
    case "$f" in
        *.sh) : ;;
        *) return 1 ;;   # un-runnable type → fail-closed (treated as not-red)
    esac
    dir=$(dirname "$ROOT/$f")
    base=$(basename "$f")
    [ -d "$dir" ] || return 1
    tmp="$dir/.red-verify-$$-$base"
    git -C "$ROOT" show ":$f" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    ( cd "$ROOT" && timeout 60 bash "$tmp" ) >/dev/null 2>&1
    rc=$?
    rm -f "$tmp"
    # Timeout (124) is ambiguous, not a clean red → fail-closed.
    [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ]
}

registered=0
for f in "${ADDED[@]}"; do
    [ -z "$f" ] && continue
    # Idempotent — skip anything already registered.
    if jq -e --arg p "$f" '(.tests_required // []) | index($p) != null' "$GOAL_FILE" >/dev/null 2>&1; then
        continue
    fi
    if run_red "$f"; then
        tmp=$(mktemp) || continue
        if jq --arg p "$f" '.tests_required = ((.tests_required // []) + [$p] | unique)' \
              "$GOAL_FILE" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$GOAL_FILE"
            registered=$((registered + 1))
        else
            rm -f "$tmp"
        fi
    fi
done

[ "$registered" -gt 0 ] && echo "red-verification: registered $registered red test(s) into tests_required[]" >&2
exit 0
