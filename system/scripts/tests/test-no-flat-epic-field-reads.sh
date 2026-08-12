#!/usr/bin/env bash
# Regression guard (t-2765): no live consumer may read the retired flat
# `epic` field (RETIRED_FIELDS, ADR-065) for task-epic-membership purposes.
# t-2765 fixed 4 sites where this had silently regressed (MCP backlog_focus,
# session_initiative.rs, CLI cmd_focus x2, backlog-reconcile.sh) — a repeat
# of the exact blind spot ADR-065's own Consequences section warns about.
# This guard makes the AC's "grep sweep" permanent instead of a one-time
# manual check, so a fifth site can't reintroduce the bug silently.
#
# Matches the actual bug shape everywhere it was found: a task/candidate
# variable literally named `t` or `task`, indexed/get'd with the "epic" key,
# in PRODUCTION code (not tests, not the ADR-065 migration script itself,
# not the documented pre-migration compat check in assert_active_epic_resolves).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0
FAIL=0

echo "== no live flat-epic-field reads (t\\[\"epic\"\\] / t.get('epic')) =="

# Candidate files: .rs, .py, .sh under system/, excluding the ADR-065
# migration script itself (its whole job is reading the retired field to
# convert it -- legitimate, not a live consumer) and vendored/build dirs.
mapfile -t FILES < <(
    find "$SYSTEM_DIR" -type f \( -name "*.rs" -o -name "*.py" -o -name "*.sh" \) \
        -not -path "*/target/*" \
        -not -path "*/scripts/migrate/*" \
        -not -path "*/node_modules/*" \
        2>/dev/null
)

VIOLATIONS=""

for f in "${FILES[@]}"; do
    # Rust: production code ends where `mod tests {` begins (t-2765 field
    # tests live inline in the same files as the fix -- structural marker,
    # not name exclusion, per pattern_count-by-structural-marker-not-name-exclusion).
    test_line=""
    if [[ "$f" == *.rs ]]; then
        test_line=$(grep -n "^mod tests {" "$f" 2>/dev/null | head -1 | cut -d: -f1)
    fi

    while IFS=: read -r lineno content; do
        [ -z "$lineno" ] && continue
        if [ -n "$test_line" ] && [ "$lineno" -ge "$test_line" ]; then
            continue  # inline test code, not a live consumer
        fi
        # The one documented exception: assert_active_epic_resolves' dual-path
        # pre-migration compat check (t-2312, has its own test coverage and
        # doc comment explaining why it reads the flat field on purpose).
        if [[ "$content" == *"flat_tag_exists"* ]]; then
            continue
        fi
        VIOLATIONS+="$f:$lineno:$content"$'\n'
    done < <(grep -nE '\b(t|task)\["epic"\]|\b(t|task)\x27epic\x27\]|\b(t|task)\.get\((\"|\x27)epic(\"|\x27)\)' "$f" 2>/dev/null)
done

if [ -z "$VIOLATIONS" ]; then
    PASS=1
    echo "  PASS: no live t[\"epic\"]/t.get('epic') consumer found outside tests, migration script, and the documented compat check"
else
    FAIL=1
    echo "  FAIL: live flat-epic-field read(s) found:"
    echo "$VIOLATIONS" | sed 's/^/    /'
    echo ""
    echo "  If this is a genuinely new legitimate exception, add it to the"
    echo "  allowlist in this script with a one-line justification -- do not"
    echo "  silently widen the grep pattern."
fi

echo ""
[ "$FAIL" -eq 0 ]
