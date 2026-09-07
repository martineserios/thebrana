#!/usr/bin/env bash
# check-no-checkout-in-main.sh — validate.sh Check 74 (ADR-094 decision 5, t-3327).
#
# The shared main checkout stays on `dev` forever: git overwrites IGNORED files without
# warning when checking out any ref that tracks the same path, and 145 tags/old branches
# still track .claude/tasks.json — a `git checkout main` in the main checkout wiped the
# live backlog ledger on 2026-09-07. Every procedure that tells a human or an agent to run
# `git checkout main|dev` (or `git switch`) in the main checkout is therefore a live
# data-loss instruction. This check fails on any such COMMAND LINE in the behavioral and
# guide surface. Prose that *mentions* the command inside backticks is not a command line
# and is not flagged; lines that mention `worktree` are the sanctioned alternative and are
# exempt.
#
# Usage: check-no-checkout-in-main.sh [repo-root]     (default: the repo this script lives in)
# Exit 0 = clean; exit 1 = offending lines printed.
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Surface: every file whose text can instruct a checkout in the shared main checkout.
SURFACE=(
    "system/skills"
    "system/rules"
    "system/procedures"
    "docs/guide/workflows/branching.md"
    ".claude/CLAUDE.md"
    "bootstrap.sh"
    "system/cli/rust/crates/brana-cli/src/main.rs"
)

# Two shapes of "command line":
#   1. a shell line: optional indent, optional "$ " prompt, then the command
#   2. a printed hint: a string literal that starts with the command (brana deploy's println!)
CMD_RE='^[[:space:]]*(\$[[:space:]]*)?git (checkout|switch) (main|dev)([[:space:]]|$|&|;|\|)'
STR_RE='["'"'"'][[:space:]]*git (checkout|switch) (main|dev)([[:space:]]|["'"'"']|$)'

hits=0
for entry in "${SURFACE[@]}"; do
    path="$ROOT/$entry"
    [ -e "$path" ] || continue
    while IFS= read -r file; do
        # grep -n both shapes; drop lines that name the sanctioned alternative.
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            case "$line" in *worktree*) continue ;; esac
            rel="${file#"$ROOT"/}"
            echo "  $rel:$line"
            hits=$((hits + 1))
        done < <(grep -nE "$CMD_RE|$STR_RE" "$file" 2>/dev/null || true)
    done < <(if [ -d "$path" ]; then find "$path" -type f \( -name '*.md' -o -name '*.sh' -o -name '*.rs' \); else printf '%s\n' "$path"; fi)
done

if [ "$hits" -gt 0 ]; then
    echo "FAIL: $hits command line(s) instruct a 'git checkout main|dev' in the shared main checkout (ADR-094 d5)."
    echo "      Ship by ref instead: git fetch origin main:main && git merge --ff-only main (on dev). Other refs: git worktree add."
    exit 1
fi
echo "OK: no 'git checkout main|dev' command lines in the behavioral/guide surface (ADR-094 d5)"
exit 0
