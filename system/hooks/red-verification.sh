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

# Reason the last run_red declined (logged to stderr so a non-registration is never silent).
DECLINE=""

# Run the staged blob of $1 (repo-relative). Returns 0 iff it ran RED (exit != 0 and not
# a timeout). Extracts the blob into the file's own directory under a temp name so the
# test's own relative imports/`source ../foo` resolve exactly as they will once committed.
# Runners by extension: .sh -> bash; .js/.mjs/.cjs -> `node --test`, executed from the
# nearest ancestor dir holding a package.json (the nested package root, t-3345) — never
# assumed to be the repo root. Any other type is fail-closed (not registered → grader
# blocks → human completes manually) and the reason is logged.
run_red() {
    local f="$1" dir base tmp rc runner pkg
    DECLINE=""
    case "$f" in
        *.sh) runner=bash ;;
        *.js|*.mjs|*.cjs)
            runner=node
            command -v node >/dev/null 2>&1 || { DECLINE="node not on PATH"; return 1; } ;;
        *) DECLINE="no runner for this file type (supported: .sh, .js, .mjs, .cjs)"; return 1 ;;
    esac
    dir=$(dirname "$ROOT/$f")
    base=$(basename "$f")
    [ -d "$dir" ] || { DECLINE="test directory missing"; return 1; }
    tmp="$dir/.red-verify-$$-$base"
    git -C "$ROOT" show ":$f" > "$tmp" 2>/dev/null || { rm -f "$tmp"; DECLINE="staged blob unreadable"; return 1; }
    # Only files that IMPORT node:test are runnable red tests. GRADER_RE also matches helpers,
    # seed scripts and other frameworks' files under tests/: running those would execute side
    # effects, or fail for lack of a global (jest/vitest) and be registered "red" although they
    # can never go green under `node --test` (Gate 3, t-3357).
    if [ "$runner" = node ] && ! grep -q -E "node:test" "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        DECLINE="not a node:test file (only files importing node:test are run; helpers and other frameworks are declined)"
        return 1
    fi
    # Working dir: repo root for bash; nearest package.json dir (bounded by ROOT) for node.
    pkg="$ROOT"
    if [ "$runner" = node ]; then
        pkg="$dir"
        while [ "$pkg" != "$ROOT" ] && [ "$pkg" != "/" ] && [ ! -f "$pkg/package.json" ]; do
            pkg=$(dirname "$pkg")
        done
    fi
    # Git exports GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE (and friends) into this hook's own
    # process. Those override path-based repo discovery, so any git commands the staged
    # test itself runs (e.g. `git init`/`commit` in a throwaway mktemp fixture) would
    # silently redirect onto THIS repo instead of the fixture — see
    # pattern_git-hook-env-leaks-into-executed-tests (t-2501 live incident, t-2602).
    # This same 5-var denylist is also unset independently in
    # tests/scripts/test-check-oracle-brana-drift.sh, tests/scripts/test-ship-brana-oracle.sh,
    # and documented in docs/architecture/features/build-receipts.md — no shared source yet
    # (t-2602 challenger finding); update all four if the list ever changes.
    if [ "$runner" = node ]; then
        ( cd "$pkg" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \
            -u GIT_OBJECT_DIRECTORY -u GIT_COMMON_DIR \
            -u NODE_OPTIONS \
            timeout -k 2 60 node --test "$tmp" ) >/dev/null 2>&1
    else
        ( cd "$ROOT" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \
            -u GIT_OBJECT_DIRECTORY -u GIT_COMMON_DIR \
            timeout -k 2 60 bash "$tmp" ) >/dev/null 2>&1
    fi
    rc=$?
    rm -f "$tmp"
    # Timeout (124) is ambiguous, not a clean red → fail-closed.
    if [ "$rc" -eq 124 ]; then DECLINE="timed out (ambiguous, not a clean red)"; return 1; fi
    if [ "$rc" -eq 0 ]; then DECLINE="ran green (exit 0) — not red"; return 1; fi
    return 0
}

registered=0
for f in "${ADDED[@]}"; do
    [ -z "$f" ] && continue
    # Already registered with an unchanged staged blob → nothing to do. A registered
    # path whose staged blob CHANGED falls through: redness must be re-earned and the
    # hash re-pinned (panel repair — without this, one edit after registration gated
    # forever with no recovery path).
    blob_hash=$(git -C "$ROOT" show ":$f" 2>/dev/null | sha256sum | cut -d' ' -f1) || blob_hash=""
    # Fail-closed: no readable staged blob → no registration, no pin. A path
    # registered without a hash would be gated by goal-completion's missing-hash
    # rule anyway; never create that state deliberately.
    [ -z "$blob_hash" ] && continue
    if jq -e --arg p "$f" --arg h "$blob_hash" \
          '((.tests_required // []) | index($p) != null) and ((.tests_hashes // {})[$p] == $h)' \
          "$GOAL_FILE" >/dev/null 2>&1; then
        continue
    fi
    if run_red "$f"; then
        # Pin the staged blob's content hash alongside registration (ADR-082 §5).
        # tests_required[] stays a plain string array — every existing consumer is
        # untouched; the hash lives in the SIBLING map tests_hashes{path: sha256}.
        # goal-completion.sh re-hashes registered paths at grade time and blocks on
        # mismatch or missing entry, closing the weaken-after-registration gap.
        # Temp file lives in the goal file's own directory so mv is an atomic
        # rename, never a cross-device copy (panel repair).
        tmp=$(mktemp "$(dirname "$GOAL_FILE")/.goal.XXXXXX") || continue
        if jq --arg p "$f" --arg h "$blob_hash" \
              '.tests_required = ((.tests_required // []) + [$p] | unique)
               | .tests_hashes = ((.tests_hashes // {}) + {($p): $h})' \
              "$GOAL_FILE" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$GOAL_FILE"
            registered=$((registered + 1))
        else
            rm -f "$tmp"
            echo "red-verification: not registering $f: could not update goal file" >&2
        fi
    else
        echo "red-verification: not registering $f: ${DECLINE:-not red}" >&2
    fi
done

[ "$registered" -gt 0 ] && echo "red-verification: registered $registered red test(s) into tests_required[]" >&2
exit 0
