#!/usr/bin/env bash
# Regression test: /brana:close Step 1 must normalize a bare orientation word
# (e.g. `/brana:close continue`, no leading `--`) to its --flag form BEFORE
# any of Step 1's three orientation checks run (t-3247).
#
# Bug: three separate points in gate-and-evidence.md's Step 1 all match
# orientation as a literal "--flag" substring on raw $ARGUMENTS: the
# close-classify.sh --arguments scan (close-classify.sh:60-65), the HARD
# GUARD ("if $ARGUMENTS contains ANY orientation flag, skip the picker"),
# and the ORIENTATION derivation ("set ORIENTATION to the flag name when
# present, auto otherwise" — consumed by session-state.md/cleanup.md for
# task-state transitions and cleanup skip-rules). A bare word reaching any
# of them silently misses the same substring scan: close-classify.sh falls
# through to file/commit-count heuristics, the HARD GUARD fails to skip the
# picker it exists to skip, and ORIENTATION derives "auto" instead of the
# intended flag — no error in any case (adversarial review, t-3247 challenger
# gate: patching only the close-classify.sh call site left the other two
# sibling sites broken by the identical mechanism). The --mode-override path
# (close-classify.sh:32-39, 56-59) is the opposite convention (bare word, no
# --) and is not what Step 1 calls.
#
# Fix: Step 1 normalizes bare orientation words to --flag form ONCE, at the
# very top of Step 1 (ORIENTATION-NORMALIZE-BLOCK in gate-and-evidence.md),
# before any of the three checks below it run — all three then operate on
# the same corrected value. Free-form focus text ($ARGUMENTS used as a Step 2
# hint, e.g. "/brana:close hooks") must NOT be touched — only the four exact
# bare orientation words normalize. This test exercises the normalize step
# feeding close-classify.sh's identical substring-scan mechanism; the HARD
# GUARD and ORIENTATION derivation use that same mechanism on the same
# post-normalization value, so a passing scan here is the direct proxy for
# both (they are prose steps evaluated by the LLM, not separately
# shell-testable).
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
