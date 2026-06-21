#!/usr/bin/env bash
# Abort orientation for /brana:close (t-1987, ADR-053 §4).
#
# Archives the current branch as a pushed tag and removes it, returning the
# task to pending. The interactive parts (asking for the reason, the dirty-tree
# decision) live in the close skill — this script receives the decisions as
# arguments and owns the git sequence, because inline phase logic loses work
# (premortem H4: unpushed tags, current-branch deletion, tag collisions).
#
# Usage:
#   close-abort.sh --task-id t-NNN --reason "why" [--dirty stash|reset|leave]
#                  [--git-root DIR] [--no-task-update]
#
# Sequence: validate → dirty-tree disposal → timestamped tag → push tag
#           (warn LOCAL ONLY on failure) → checkout dev (feature-branch base;
#           falls back to main) → branch -D → task → pending (unless --no-task-update).
#
# Exit codes: 0 success (push failure still 0 — warned, not fatal)
#             2 contract violation (no reason, on main, dirty without --dirty)

set -uo pipefail

TASK_ID=""
REASON=""
DIRTY=""
GIT_ROOT="$PWD"
TASK_UPDATE=true
REASON_SET=false
while [ $# -gt 0 ]; do
    case "$1" in
        --task-id)        TASK_ID="$2"; shift 2 ;;
        --reason)         REASON="$2"; REASON_SET=true; shift 2 ;;
        --dirty)          DIRTY="$2"; shift 2 ;;
        --git-root)       GIT_ROOT="$2"; shift 2 ;;
        --no-task-update) TASK_UPDATE=false; shift ;;
        *) echo "close-abort: unknown argument $1" >&2; exit 2 ;;
    esac
done

if [ "$REASON_SET" = false ] || [ -z "$REASON" ]; then
    echo "close-abort: --reason is required — an abort without a recorded reason is unrecoverable context loss" >&2
    exit 2
fi

BRANCH=$(git -C "$GIT_ROOT" branch --show-current)
if [ -z "$BRANCH" ] || [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    echo "close-abort: refusing to abort '$BRANCH' — abort archives a feature branch, not the mainline" >&2
    exit 2
fi

# Default branch to land on after the abort. Feature branches are cut off dev
# (dev-first model), so return there; fall back to main/master if dev is absent.
DEFAULT_BRANCH="dev"
if ! git -C "$GIT_ROOT" rev-parse --verify -q dev >/dev/null; then
    DEFAULT_BRANCH="main"
    git -C "$GIT_ROOT" rev-parse --verify -q main >/dev/null || DEFAULT_BRANCH="master"
fi

# ── Dirty-tree disposal — explicit decision required, never a silent default ──
if [ -n "$(git -C "$GIT_ROOT" status --porcelain)" ]; then
    case "$DIRTY" in
        stash)
            git -C "$GIT_ROOT" stash push -u -m "abort: $REASON ($(date +%Y-%m-%d))" >/dev/null
            ;;
        reset)
            git -C "$GIT_ROOT" reset --hard -q
            git -C "$GIT_ROOT" clean -fdq
            ;;
        leave)
            echo "close-abort: WARNING — leaving dirty changes in the working tree; they carry over to $DEFAULT_BRANCH" >&2
            ;;
        "")
            echo "close-abort: working tree is dirty — pass --dirty stash|reset|leave (no silent default for uncommitted work)" >&2
            exit 2
            ;;
        *)
            echo "close-abort: invalid --dirty '$DIRTY' (valid: stash reset leave)" >&2
            exit 2
            ;;
    esac
fi

# ── Timestamped archive tag; same-day re-abort gets a time suffix ─────────────
BRANCH_BASE=$(basename "$BRANCH")
TAG="aborted/${BRANCH_BASE}-$(date +%Y%m%d)"
if git -C "$GIT_ROOT" rev-parse --verify -q "refs/tags/$TAG" >/dev/null; then
    TAG="${TAG}-$(date +%H%M%S)"
fi
git -C "$GIT_ROOT" tag "$TAG" "$BRANCH"

# ── Push the tag — unpushed tags die with the machine ─────────────────────────
if git -C "$GIT_ROOT" push origin "refs/tags/$TAG" >/dev/null 2>&1; then
    echo "close-abort: archived as $TAG (pushed)"
else
    echo "close-abort: WARNING — tag $TAG is LOCAL ONLY (push failed or no remote); the archive does not survive machine loss until pushed" >&2
fi

# ── Leave the branch, then delete it (deleting the current branch fails) ──────
# Plain checkout can refuse when --dirty leave carries changes that conflict
# with the target; -m three-way-merges them across (conflicts surface in the
# working tree for the user to resolve — that's the "leave" contract).
if ! git -C "$GIT_ROOT" checkout -q "$DEFAULT_BRANCH" 2>/dev/null; then
    if ! git -C "$GIT_ROOT" checkout -q -m "$DEFAULT_BRANCH" 2>/dev/null; then
        echo "close-abort: ERROR — cannot switch to $DEFAULT_BRANCH; branch NOT deleted (tag $TAG already archived)" >&2
        exit 1
    fi
fi
git -C "$GIT_ROOT" branch -D "$BRANCH" >/dev/null

echo "close-abort: branch $BRANCH removed; recover with: git checkout $TAG"

# ── Task back to pending with the reason on record ────────────────────────────
if [ "$TASK_UPDATE" = true ] && [ -n "$TASK_ID" ]; then
    if command -v brana >/dev/null 2>&1; then
        brana backlog set "$TASK_ID" status pending >/dev/null 2>&1 || \
            echo "close-abort: WARNING — failed to set $TASK_ID to pending" >&2
        brana backlog set "$TASK_ID" context --append "$(date +%Y-%m-%d): ABORTED — $REASON (archive: $TAG)" >/dev/null 2>&1 || \
            echo "close-abort: WARNING — failed to append abort reason to $TASK_ID" >&2
    else
        echo "close-abort: WARNING — brana binary not found; update $TASK_ID manually (status pending, reason: $REASON)" >&2
    fi
fi

exit 0
