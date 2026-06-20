#!/usr/bin/env bash
#
# secret-scan.sh — block commits that stage high-signal secrets (t-2138)
#
# The local net that GitHub push protection provides remotely. A 2026-06-19
# incident leaked a live Slack token into git via a session-captured curl that
# the pattern-export pipeline committed; only GitHub's push protection caught it.
# This hook catches credentials at COMMIT time, before they ever enter history.
#
# Two invocation modes:
#   1. --staged          git pre-commit hook / direct: scans `git diff --cached`.
#                        (git stages `-a` content into the index before pre-commit
#                        runs, so --cached is correct there.)
#   2. (JSON on stdin)   PreToolUse(Bash) hook: only acts on `git commit` calls,
#                        then scans the diff. This is the layer that would have
#                        caught the incident (the leak came via a CC commit).
#                        `git commit -a` stages tracked changes only when git runs,
#                        AFTER this hook fires — so --cached is empty. We detect
#                        -a/--all and scan `git diff HEAD`, with an empty-staged
#                        fallback as a second net (challenger CRITICAL, t-2138).
#
# Detection is high-precision (known token formats only) to avoid false
# positives that train users to bypass. The redaction allowlist is applied to
# the matched TOKEN, not the whole line — a real token on a line that also says
# "example" must still be caught (that was the original leak scenario;
# challenger HIGH, t-2138).
#
# Exit codes:
#   0 — no secret found (or not a commit call), allow
#   2 — secret found, block (CC surfaces stderr to the model; git rejects on non-zero)
#
# Escape hatch: BRANA_SECRET_SCAN_BYPASS=1 (deliberate env, NOT a shared /tmp
# sentinel — a security control must not be disabled by unrelated test harnesses).

set -uo pipefail

[ "${BRANA_SECRET_SCAN_BYPASS:-}" = "1" ] && exit 0

command=""
diff_target="--cached"

if [ "${1:-}" = "--staged" ]; then
    :   # git-hook / direct mode: scan the index as-is.
else
    # PreToolUse mode: JSON tool-call on stdin. Read only if stdin is not a tty.
    if [ ! -t 0 ]; then
        input=$(cat)
        if [ -n "${input//[[:space:]]/}" ]; then
            command=$(printf '%s' "$input" | jq -r '.tool_input.command // .input.command // empty' 2>/dev/null || true)
            if [ -n "$command" ]; then
                case "$command" in
                    *"git commit"*) ;;   # a commit call — fall through to scan
                    *) exit 0 ;;          # anything else — not our concern
                esac
                # `git commit -a/--all` content is not staged when this hook fires.
                # Scan working-tree-vs-HEAD to catch it.
                if printf '%s' "$command" | grep -qE 'commit\b.*([[:space:]]-[a-zA-Z]*a[a-zA-Z]*\b|[[:space:]]--all\b)'; then
                    diff_target="HEAD"
                fi
            fi
        fi
    fi
fi

# Collect newly-added lines (ignore the +++ file header).
added=$(git diff "$diff_target" --unified=0 2>/dev/null | grep '^+' | grep -v '^+++' || true)

# Safety net: nothing staged but we're in --cached mode → a `-a` commit we did
# not detect from the command string. Fall back to the working-tree diff.
if [ -z "$added" ] && [ "$diff_target" = "--cached" ]; then
    added=$(git diff HEAD --unified=0 2>/dev/null | grep '^+' | grep -v '^+++' || true)
fi

[ -z "$added" ] && exit 0

# High-signal secret patterns: name|regex (ERE).
patterns=(
    "Slack token|xox[baprs]-[A-Za-z0-9-]{20,}"
    "AWS access key id|AKIA[0-9A-Z]{16}"
    "GitHub token|gh[pousr]_[A-Za-z0-9]{36,}"
    "Google API key|AIza[0-9A-Za-z_-]{35}"
    "Private key block|-----BEGIN [A-Z ]*PRIVATE KEY-----"
)

# A match is a real finding unless the matched TOKEN itself is a redaction
# placeholder. Applied to the matched value, NOT the line — a real token on a
# line that also says "example" must still be caught (challenger HIGH, t-2138).
found=()
for entry in "${patterns[@]}"; do
    name="${entry%%|*}"
    regex="${entry#*|}"
    while IFS= read -r m; do
        [ -z "$m" ] && continue
        case "$m" in
            *REDACTED*|*redacted*|*EXAMPLE*|*example*|*PLACEHOLDER*|*placeholder*) continue ;;
        esac
        found+=("$name")
        break
    done < <(printf '%s\n' "$added" | grep -oE -e "$regex" || true)
done

if [ ${#found[@]} -gt 0 ]; then
    {
        echo ""
        echo "BLOCKED: staged changes contain what looks like a live secret."
        echo ""
        echo "Detected:"
        for f in "${found[@]}"; do
            echo "  - $f"
        done
        echo ""
        echo "The value is NOT printed here on purpose. To resolve:"
        echo "  1. Unstage / remove the secret from the staged files."
        echo "  2. Rotate it if it was ever real (assume compromised)."
        echo "  3. If this is a false positive, mark the token REDACTED/EXAMPLE,"
        echo "     or bypass deliberately: BRANA_SECRET_SCAN_BYPASS=1 git commit ..."
        echo ""
        echo "See system/rules/git-discipline.md and t-2138."
        echo ""
    } >&2
    exit 2
fi

exit 0
