#!/usr/bin/env bash
# Regression test: /brana:close Step 1 must normalize a bare orientation word
# (e.g. `/brana:close continue`, no leading `--`) to its --flag form before
# passing $ARGUMENTS to close-classify.sh's --arguments string-contains scan
# (t-3247).
#
# Bug: close-classify.sh's --arguments path only recognizes "--continue" etc
# as a substring (close-classify.sh:60-65). A bare word reaching gate-and-
# evidence.md's Step 1 invocation (line ~321) silently misses that scan and
# falls through to the file/commit-count heuristics — classification degrades
# without any error. The --mode-override path (close-classify.sh:32-39, 56-59)
# is the opposite convention (bare word, no --) and is not what Step 1 calls.
#
# Fix: Step 1 normalizes bare orientation words to --flag form BEFORE the
# close-classify.sh invocation (ORIENTATION-NORMALIZE-BLOCK in gate-and-
# evidence.md), so both entry conventions converge on one string. Free-form
# focus text ($ARGUMENTS used as a Step 2 hint, e.g. "/brana:close hooks")
# must NOT be touched — only the four exact bare orientation words normalize.
#
# The snippet is EXTRACTED from system/skills/close/phases/gate-and-evidence.md
# so the test exercises the shipped procedure text, not a copy (t-1978 rot class).
#
# Run: bash tests/procedures/test-close-orientation-normalize.sh

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected [$expected], got [$actual]"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== test-close-orientation-normalize.sh ==="
echo ""

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PHASE_MD="$REPO_ROOT/system/skills/close/phases/gate-and-evidence.md"
CLASSIFY="$REPO_ROOT/system/scripts/close-classify.sh"

if [ ! -f "$PHASE_MD" ]; then
    echo "ERROR: $PHASE_MD not found"; exit 1
fi
if [ ! -x "$CLASSIFY" ]; then
    echo "ERROR: $CLASSIFY missing or not executable"; exit 1
fi

NORMALIZE_SNIPPET=$(sed -n '/<!-- ORIENTATION-NORMALIZE-BLOCK -->/,/<!-- \/ORIENTATION-NORMALIZE-BLOCK -->/p' "$PHASE_MD" \
    | sed '1d;$d' | grep -v '^```')
if [ -z "$NORMALIZE_SNIPPET" ]; then
    echo "ERROR: ORIENTATION-NORMALIZE-BLOCK markers missing or empty in $PHASE_MD"; exit 1
fi
if ! echo "$NORMALIZE_SNIPPET" | grep -q 'ARGUMENTS='; then
    echo "ERROR: ORIENTATION-NORMALIZE-BLOCK does not set ARGUMENTS — markers moved?"; exit 1
fi

# Runs the extracted normalize snippet with $1 as the raw $ARGUMENTS, then
# feeds the (possibly rewritten) ARGUMENTS straight into close-classify.sh —
# the same two-step pipeline Step 1 performs.
normalize_then_classify() {
    local raw_arguments="$1" commit_count="${2:-1}" changed_files="${3:-docs/note.md}"
    ARGUMENTS="$raw_arguments"
    eval "$NORMALIZE_SNIPPET"
    echo "$changed_files" | bash "$CLASSIFY" --commit-count "$commit_count" --arguments "$ARGUMENTS"
}

echo "Bare orientation words normalize to --flag form (force weight)"
MODE=$(normalize_then_classify "continue")
assert_eq "bare 'continue' → INSTANT (auto would be NANO)" "INSTANT" "$MODE"

MODE=$(normalize_then_classify "finish")
assert_eq "bare 'finish' → INSTANT (auto would be NANO)" "INSTANT" "$MODE"

MODE=$(normalize_then_classify "patterns" 5 "src/main.rs")
assert_eq "bare 'patterns' → LIGHT-INLINE (auto would be INSTANT)" "LIGHT-INLINE" "$MODE"

MODE=$(normalize_then_classify "abort" 5 "src/main.rs")
assert_eq "bare 'abort' → NANO (auto would be INSTANT)" "NANO" "$MODE"

echo ""
echo 'Already-flagged $ARGUMENTS passes through unchanged'
MODE=$(normalize_then_classify "--continue")
assert_eq "'--continue' stays --continue → INSTANT" "INSTANT" "$MODE"

echo ""
echo "Free-form focus text is NOT touched (Step 2 hint use, e.g. /brana:close hooks)"
MODE=$(normalize_then_classify "hooks")
assert_eq "'hooks' → NANO (not treated as an orientation)" "NANO" "$MODE"

MODE=$(normalize_then_classify "")
assert_eq "empty \$ARGUMENTS → NANO (unaffected)" "NANO" "$MODE"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

[ "$FAIL" -eq 0 ] || exit 1
