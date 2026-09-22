#!/usr/bin/env bash
# check-private-state-untracked.sh — validate.sh Check 75 (t-3352).
#
# thebrana is a PUBLIC repo. system/state/portfolio.md and tasks-portfolio.json hold
# private client/venture data (fees, ids, names) and must never be committed here.
# They are pushed to the private brana-knowledge repo instead (see
# docs/architecture/features/private-state-sync.md). This check fails when either file
# is TRACKED, or is not gitignored (an ignored path can't be re-added by a blanket
# `git add system/state/`, which is exactly what sync-state.sh --auto-commit does).
#
# Usage: check-private-state-untracked.sh [repo-root]   (default: current git root)
set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PRIVATE_FILES=(
    "system/state/portfolio.md"
    "system/state/tasks-portfolio.json"
)

BAD=0
for f in "${PRIVATE_FILES[@]}"; do
    if git -C "$ROOT" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
        echo "TRACKED: $f is committed to this public repo — run: git rm --cached $f"
        BAD=1
    fi
    # The ignore rule must live in a committed .gitignore. check-ignore -q also passes on
    # .git/info/exclude or a global core.excludesFile, which protect only THIS clone.
    # `check-ignore -q` exits 0 ONLY when the path is really ignored. `-v` alone exits 0 even
    # when the matching rule is a NEGATED one ('!path'), which re-includes the file — so gate on
    # -q first, then ask -v only for the source file of the rule.
    if git -C "$ROOT" check-ignore -q "$f" 2>/dev/null; then
        src=$(git -C "$ROOT" check-ignore -v "$f" 2>/dev/null | cut -f1)
    else
        src=""
    fi
    # The rule's source must be a .gitignore that is itself TRACKED and repo-relative. An
    # untracked nested .gitignore, or a global core.excludesFile (absolute path), protects only
    # this clone/machine — a fresh clone or CI would not have it.
    srcfile="${src%%:*}"
    case "$srcfile" in
        /*|"") ok_src=0 ;;
        *.gitignore)
            if git -C "$ROOT" ls-files --error-unmatch -- "$srcfile" >/dev/null 2>&1; then ok_src=1; else ok_src=0; fi ;;
        *) ok_src=0 ;;
    esac
    if [ "$ok_src" -ne 1 ]; then
        echo "NOT GITIGNORED (in a TRACKED, repo-relative .gitignore): $f — add it to a committed .gitignore so 'git add system/state/' cannot re-publish it"
        BAD=1
    fi
done
exit "$BAD"
