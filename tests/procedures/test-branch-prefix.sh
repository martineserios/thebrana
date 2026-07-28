#!/usr/bin/env bash
# Regression test: resolve_branch_prefix() — one authority for git branch prefixes (t-2494).
#
# THE BUG. Two rule sources disagreed on the prefix for the same task:
#   - system/rules/task-convention.md keyed the mapping on task.KIND
#   - system/skills/backlog/phases/start.md keyed it on task.WORK_TYPE
# Every kind:fix task carrying work_type:implement resolved to `feat/` under start.md
# and `fix/` under task-convention.md. Three P1/P2 defect branches were labelled feat/
# before anyone noticed, and the conflict was resolved by hand twice.
#
# THE RESOLUTION. `kind` is authoritative: it names what the change DOES. `work_type`
# is a cognitive-mode label ("this is coding work") and is deliberately orthogonal —
# task-convention.md itself says kind:refactor tasks use work_type:implement, which
# confirms work_type was never meant to carry change class.
#
# WHY THE FALLBACK IS LOAD-BEARING, NOT VESTIGIAL. 488 of 2158 tasks (22%) carry
# kind:null. Demoting work_type entirely would leave a fifth of the backlog with no
# prefix source at all, so the fallback chain is exercised constantly and is tested
# here as a first-class path rather than an edge case.
#
# The function under test is extracted from system/skills/_shared/branch-prefix.md
# so this test exercises the shipped source, not a copy (t-1978 rot class).
#
# Run: bash tests/procedures/test-branch-prefix.sh

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

REPO_ROOT=$(git rev-parse --show-toplevel)
PREFIX_MD="$REPO_ROOT/system/skills/_shared/branch-prefix.md"
TMPDIR_T=$(mktemp -d)
trap 'rm -rf "$TMPDIR_T"' EXIT

if [ ! -f "$PREFIX_MD" ]; then
    echo "ERROR: $PREFIX_MD does not exist — the shared authority block is missing"
    exit 1
fi

# Extract by NAMED MARKER, not by position or content substring (t-2493).
sed -n '/<!-- BRANCH-PREFIX-BLOCK -->/,/<!-- \/BRANCH-PREFIX-BLOCK -->/p' "$PREFIX_MD" \
| sed '1d;$d' \
| sed '/^```/d' > "$TMPDIR_T/prefix.sh"

if [ ! -s "$TMPDIR_T/prefix.sh" ]; then
    echo "ERROR: BRANCH-PREFIX-BLOCK markers missing or empty in $PREFIX_MD"
    exit 1
fi
if ! grep -q 'resolve_branch_prefix' "$TMPDIR_T/prefix.sh"; then
    echo "ERROR: BRANCH-PREFIX-BLOCK does not contain resolve_branch_prefix() — markers drifted"
    exit 1
fi

source "$TMPDIR_T/prefix.sh"

echo "=== kind is authoritative (every kind value present in tasks.json) ==="
assert_eq "kind:feature  -> feat"     "feat"     "$(resolve_branch_prefix feature implement)"
assert_eq "kind:fix      -> fix"      "fix"      "$(resolve_branch_prefix fix implement)"
assert_eq "kind:refactor -> refactor" "refactor" "$(resolve_branch_prefix refactor implement)"
assert_eq "kind:research -> research" "research" "$(resolve_branch_prefix research research)"
assert_eq "kind:docs     -> docs"     "docs"     "$(resolve_branch_prefix docs chore)"
assert_eq "kind:design   -> design"   "design"   "$(resolve_branch_prefix design implement)"
assert_eq "kind:ops      -> chore"    "chore"    "$(resolve_branch_prefix ops infra)"
assert_eq "kind:test     -> test"     "test"     "$(resolve_branch_prefix test implement)"

echo "=== AC2: the exact reported conflict ==="
# kind:fix + work_type:implement resolved to feat/ under start.md and fix/ under
# task-convention.md. It must now resolve to fix/ through the documented path.
assert_eq "kind:fix + work_type:implement -> fix (NOT feat)" "fix" \
    "$(resolve_branch_prefix fix implement)"
# The three branches cut by hand on 2026-07-27 (t-2487/t-2478/t-2491) were all this shape.
assert_eq "kind:refactor + work_type:implement -> refactor (NOT feat)" "refactor" \
    "$(resolve_branch_prefix refactor implement)"

echo "=== work_type fallback — load-bearing, 22% of tasks have kind:null ==="
assert_eq "kind empty + implement -> feat"     "feat"     "$(resolve_branch_prefix '' implement)"
assert_eq "kind empty + fix       -> fix"      "fix"      "$(resolve_branch_prefix '' fix)"
assert_eq "kind empty + research  -> research" "research" "$(resolve_branch_prefix '' research)"
assert_eq "kind empty + chore     -> chore"    "chore"    "$(resolve_branch_prefix '' chore)"
assert_eq "kind empty + infra     -> chore"    "chore"    "$(resolve_branch_prefix '' infra)"
assert_eq "kind empty + review    -> review"   "review"   "$(resolve_branch_prefix '' review)"
assert_eq "kind empty + design    -> design"   "design"   "$(resolve_branch_prefix '' design)"
assert_eq "kind 'null' literal    -> feat"     "feat"     "$(resolve_branch_prefix null implement)"

echo "=== unknown / absent inputs degrade to feat, never to empty ==="
assert_eq "unknown kind falls through to work_type" "fix" "$(resolve_branch_prefix banana fix)"
assert_eq "both empty -> feat"                      "feat" "$(resolve_branch_prefix '' '')"
assert_eq "both unknown -> feat"                    "feat" "$(resolve_branch_prefix banana kumquat)"

echo "=== output is a bare prefix: no slash, no whitespace, never empty ==="
for k in feature fix refactor research docs design ops test '' banana; do
    out=$(resolve_branch_prefix "$k" implement)
    TOTAL=$((TOTAL + 1))
    if [ -n "$out" ] && [[ "$out" != */* ]] && [[ "$out" != *[[:space:]]* ]]; then
        echo "  PASS: kind:[$k] emits a bare prefix [$out]"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: kind:[$k] emitted [$out] — must be non-empty, no slash, no whitespace"
        FAIL=$((FAIL + 1))
    fi
done

echo "=== every emitted prefix is one CLAUDE.md accepts as a work-type ==="
# CLAUDE.md §Branch naming enumerates the legal work-type segment. A mapping that
# emits a prefix outside that list produces branch names the convention forbids.
CLAUDE_MD="$REPO_ROOT/.claude/CLAUDE.md"
for k in feature fix refactor research docs design ops test; do
    out=$(resolve_branch_prefix "$k" implement)
    TOTAL=$((TOTAL + 1))
    if grep -q "\`$out\`" "$CLAUDE_MD"; then
        echo "  PASS: prefix [$out] (from kind:$k) is listed in CLAUDE.md"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: prefix [$out] (from kind:$k) is NOT listed in CLAUDE.md work-types"
        FAIL=$((FAIL + 1))
    fi
done

echo "=== start.md must reference the authority, not restate a mapping (AC1) ==="
START_MD="$REPO_ROOT/system/skills/backlog/phases/start.md"
TOTAL=$((TOTAL + 1))
if grep -q "branch-prefix.md\|resolve_branch_prefix" "$START_MD"; then
    echo "  PASS: start.md references the shared authority"
    PASS=$((PASS + 1))
else
    echo "  FAIL: start.md does not reference branch-prefix.md — it restates a mapping"
    FAIL=$((FAIL + 1))
fi
# The old work_type-keyed table is what drifted. Its signature line must be gone.
TOTAL=$((TOTAL + 1))
if grep -qE '^\s*-\s*`implement`\s*/\s*`feat`\s*(→|->)\s*`feat`' "$START_MD"; then
    echo "  FAIL: start.md still carries the standalone work_type→prefix table"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: start.md no longer carries a standalone work_type→prefix table"
    PASS=$((PASS + 1))
fi

echo ""
echo "=== Summary ==="
echo "Total: $TOTAL | Passed: $PASS | Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
