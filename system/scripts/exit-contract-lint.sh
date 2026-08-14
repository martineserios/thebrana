#!/usr/bin/env bash
# exit-contract-lint.sh — new callers of exit-status-contract helpers must
# branch on failure (t-2888).
#
# WHY. resolve_epic_ancestor's exit contract (empty+exit0 = no epic vs exit1 =
# lookup failed) was independently dropped by three new call sites (t-2263,
# t-2843, t-2845's first draft) despite a bolded worked example in the helper's
# own doc. Every incident had the same mechanical signature: a bare
# `VAR=$(helper ...)` that never branches on the exit status, collapsing
# "lookup failed" into "no result". That signature is greppable — this lint
# catches it at Challenger-gate time instead of trusting each new author to
# re-read the shared doc. Judging whether a *branched* call distinguishes every
# documented outcome stays with the Challenger; the lint owns the mechanical
# class only.
#
# REGISTRY (self-maintaining — no hardcoded helper list). Scans registry-dir
# *.md files for a `# Exit contract` comment marker; the next function
# definition line names the policed helper. Document a new helper's contract
# with that marker and the lint covers it automatically.
#
# Usage:
#   exit-contract-lint.sh [RANGE]                lint `git diff RANGE`
#                                                (default: main...HEAD)
#   exit-contract-lint.sh --stdin                lint a unified diff from stdin
#   exit-contract-lint.sh --registry-dir DIR     override the registry
#                                                (default: system/skills/_shared)
#
# A call site is CLEAN when the added line branches on exit status:
#   if/elif/while/until-wrapped call, `||` on the call line, or `$?` checked
#   within the next 2 lines. `&&`-only chaining is a violation — it handles
#   success, not failure. Files under tests/ and the registry docs themselves
#   are exempt (fixtures and worked examples legitimately show bare calls).
#
# Exit codes:
#   0  clean
#   1  violations (one `path:line: helper ...` line per violation)
#   2  registry missing or no marked helpers found (fail CLOSED — a broken
#      marker regex must not silently turn the lint into a no-op)
#
# Wired into: system/skills/_shared/challenger-gate.md (mechanical pre-check).
# Tests: tests/procedures/test-exit-contract-lint.sh

set -uo pipefail

REGISTRY_DIR=""
USE_STDIN=0
RANGE="main...HEAD"

while [ $# -gt 0 ]; do
    case "$1" in
        --stdin) USE_STDIN=1; shift ;;
        --registry-dir) REGISTRY_DIR="${2:?--registry-dir needs a value}"; shift 2 ;;
        -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) RANGE="$1"; shift ;;
    esac
done

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
[ -z "$REGISTRY_DIR" ] && REGISTRY_DIR="$REPO_ROOT/system/skills/_shared"

if [ ! -d "$REGISTRY_DIR" ]; then
    echo "exit-contract-lint: registry dir not found: $REGISTRY_DIR" >&2
    exit 2
fi

# ── Discover marked helpers: `# Exit contract` marker → next function def ────
declare -A CONTRACT_DOC   # helper name → doc path (for the report line)
declare -A REGISTRY_BASE  # registry doc basenames → 1 (exempt from linting)
# Plain counter: ${#CONTRACT_DOC[@]} on an empty assoc array trips `set -u`
# on this bash, silently skipping the fail-closed branch below.
helper_count=0
for doc in "$REGISTRY_DIR"/*.md; do
    [ -f "$doc" ] || continue
    name=$(awk '
        /#[[:space:]]*Exit contract/ { armed = NR }
        armed && NR <= armed + 10 && match($0, /^[a-zA-Z_][a-zA-Z0-9_]*\(\)/) {
            print substr($0, RSTART, RLENGTH - 2); armed = 0
        }' "$doc")
    for n in $name; do
        CONTRACT_DOC[$n]="$doc"
        REGISTRY_BASE[$(basename "$doc")]=1
        helper_count=$((helper_count + 1))
    done
done

if [ "$helper_count" -eq 0 ]; then
    echo "exit-contract-lint: no '# Exit contract' marked helpers found in $REGISTRY_DIR (fail closed)" >&2
    exit 2
fi

# ── Lint the diff ────────────────────────────────────────────────────────────
violations=0
file="" skip_file=0 ln=0
pending_helper="" pending_line=0 pending_file="" pending_doc="" pending_window=0

flush_pending() {
    if [ -n "$pending_helper" ]; then
        printf '%s:%s: %s called without branching on exit status (contract: %s)\n' \
            "$pending_file" "$pending_line" "$pending_helper" "$pending_doc"
        violations=$((violations + 1))
        pending_helper=""
    fi
}

lint_diff() {
    local raw line h
    while IFS= read -r raw; do
        case "$raw" in
            +++*)
                flush_pending
                file="${raw#+++ }"; file="${file#b/}"
                skip_file=0
                # Exempt: test files (fixtures) and registry docs (worked
                # examples). Registry exemption is scoped to the ACTIVE
                # registry dir, not any _shared/ repo-wide (challenger, t-2888).
                file_dir=$(dirname "$file")
                if [[ "$file" =~ (^|/)tests/ ]] \
                   || [ -n "${REGISTRY_BASE[$(basename "$file")]:-}" ] \
                   || [[ "$REGISTRY_DIR" == */"$file_dir" || "$REGISTRY_DIR" == "$file_dir" ]]; then
                    skip_file=1
                fi
                continue ;;
            ---*|diff\ *|index\ *) continue ;;
            @@*)
                flush_pending
                ln=$(sed -E 's/^@@ -[0-9]+(,[0-9]+)? \+([0-9]+).*/\2/' <<<"$raw")
                continue ;;
        esac
        [ "$skip_file" -eq 1 ] && continue
        case "$raw" in
            -*) continue ;;         # removed lines never advance the new file
            +*) line="${raw#+}" ;;
            *)  line="${raw# }" ;;  # context line
        esac
        cur=$ln; ln=$((ln + 1))

        # Resolve an open window: `$?` within 2 lines of the call clears it.
        if [ -n "$pending_helper" ]; then
            if [[ "$line" == *'$?'* ]]; then
                pending_helper=""
            else
                pending_window=$((pending_window - 1))
                [ "$pending_window" -le 0 ] && flush_pending
            fi
        fi

        [[ "$raw" == +* ]] || continue                      # only ADDED lines can violate
        [[ "$line" =~ ^[[:space:]]*# ]] && continue         # comments
        for h in "${!CONTRACT_DOC[@]}"; do
            [[ "$line" =~ (^|[^a-zA-Z0-9_])"$h"([^a-zA-Z0-9_]|$) ]] || continue
            [[ "$line" == *"$h()"* ]] && continue           # function definition
            prefix="${line%%"$h"*}"   # text before the first occurrence
            suffix="${line#*"$h"}"    # text after it
            # Invocation syntax required — prose/doc mentions of the helper name
            # are not call sites (pre-edit challenger finding #2, t-2888).
            # A call is: command substitution `$(h ...`, or the helper in
            # command position — line start (any indentation), after a
            # separator (; & | { (), or after do/then/else (post-build
            # challenger finding #1: indented and keyword-prefixed direct
            # calls are the common real-world shapes).
            if ! [[ "$prefix" =~ \$\([[:space:]]*$ ]] \
               && ! [[ "$prefix" =~ ^[[:space:]]*$ ]] \
               && ! [[ "$prefix" =~ [\;\&\|\{\(][[:space:]]*$ ]] \
               && ! [[ "$prefix" =~ (^|[[:space:]\;\&\|\{\(])(do|then|else)[[:space:]]+$ ]]; then
                continue
            fi
            # Branched? A guarding keyword must still be OPEN at the call —
            # i.e. no `;` between it and the helper (`| while read; do h` is
            # NOT guarded: the while tests read, the `;` closed its condition).
            if [[ "$prefix" =~ (^|[[:space:]\;\&\|\{\(])(if|elif|while|until)[[:space:]][^\;]*$ ]]; then
                continue
            fi
            # `||` AFTER the call handles this call's failure; before it, the
            # previous command's (post-build challenger finding #1).
            [[ "$suffix" == *'||'* ]] && continue
            flush_pending   # an older unresolved call reports before we track this one
            pending_helper="$h"
            pending_line="$cur"
            pending_file="$file"
            pending_doc="${CONTRACT_DOC[$h]}"
            pending_window=2
            break
        done
    done
    flush_pending
}

if [ "$USE_STDIN" -eq 1 ]; then
    lint_diff
else
    lint_diff < <(git -C "$REPO_ROOT" diff "$RANGE")
fi

if [ "$violations" -gt 0 ]; then
    echo "exit-contract-lint: $violations violation(s) — callers of exit-contract helpers must branch on failure" >&2
    exit 1
fi
echo "exit-contract-lint: clean ($helper_count helper(s) policed)"
exit 0
