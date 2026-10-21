#!/usr/bin/env bash
# Structural tests for t-2991: proactive terminal diagrams.
# Validates: work-preferences.md carries the trigger heuristic + pointer,
# the AUTHORED always-load budget stays within cap, the skill file exists
# with Read-only allowed-tools and covers the four v1 worked-example styles,
# and the skill registry references it.
# Run: bash tests/skills/test_terminal_diagrams_skill.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RULE="$REPO_ROOT/system/rules/work-preferences.md"
SKILL="$REPO_ROOT/system/skills/terminal-diagrams/SKILL.md"
REGISTRY="$REPO_ROOT/docs/reference/skills.md"

PASS=0
FAIL=0
TOTAL=0

assert() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" file="$3"
    TOTAL=$((TOTAL + 1))
    if grep -q "$needle" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$needle' in $(basename "$file"))"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== test_terminal_diagrams_skill.sh ==="

# ── Test 1: trigger heuristic lives in work-preferences.md, not a new rule ──
echo "Test 1: trigger heuristic in existing always-load rule"
assert "work-preferences.md exists" "true" "$([ -f "$RULE" ] && echo true || echo false)"
assert_contains "still always-load: true" "always-load: true" "$RULE"
assert_contains "Terminal diagrams section present" "## Terminal diagrams" "$RULE"
assert_contains "pointer to the skill" "system/skills/terminal-diagrams/SKILL.md" "$RULE"
assert "no standalone rule file created" "false" "$([ -f "$REPO_ROOT/system/rules/terminal-diagrams.md" ] && echo true || echo false)"

# ── Test 2: AUTHORED always-load budget stays within cap (regression guard) ──
echo "Test 2: AUTHORED budget within cap"
BUDGET_OUT="$(bash "$REPO_ROOT/system/scripts/context-budget.sh" --report 2>&1 || true)"
OVER=$(echo "$BUDGET_OUT" | grep -c "headroom: -" || true)
assert "AUTHORED pool not over cap" "0" "${OVER:-0}"

# ── Test 3: skill file exists with correct frontmatter ──
echo "Test 3: skill file frontmatter"
assert "SKILL.md exists" "true" "$([ -f "$SKILL" ] && echo true || echo false)"
assert_contains "name: terminal-diagrams" "^name: terminal-diagrams" "$SKILL"
assert_contains "description present" "^description:" "$SKILL"
assert_contains "allowed-tools present" "^allowed-tools:" "$SKILL"
assert_contains "Read in allowed-tools" "Read" "$SKILL"

# ── Test 4: skill is read-as-reference, not a mutating procedure ──
echo "Test 4: no write-capable tools"
for tool in Write Edit Bash NotebookEdit; do
    TOTAL=$((TOTAL + 1))
    if grep -A5 "^allowed-tools:" "$SKILL" 2>/dev/null | grep -q "$tool"; then
        echo "  FAIL: allowed-tools must not include $tool (read-as-reference skill)"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: allowed-tools excludes $tool"
        PASS=$((PASS + 1))
    fi
done

# ── Test 5: general composable primitives + 4 worked-example styles present ──
echo "Test 5: diagram vocabulary coverage"
assert_contains "box-drawing characters documented" "─\|│\|├──\|└──" "$SKILL"
assert_contains "flow/pipeline example" "[Ff]low\|[Pp]ipeline" "$SKILL"
assert_contains "tree/hierarchy example" "[Tt]ree\|[Hh]ierarchy" "$SKILL"
assert_contains "comparison table example" "[Cc]omparison" "$SKILL"
assert_contains "architecture/component example" "[Aa]rchitecture\|[Cc]omponent" "$SKILL"
assert_contains "general composition guidance (not closed list)" "compos" "$SKILL"

# ── Test 6: feature spec exists and reflects the real (post-challenger) design ──
echo "Test 6: feature spec present and consistent"
SPEC="$REPO_ROOT/docs/architecture/features/terminal-diagrams.md"
assert "feature spec exists" "true" "$([ -f "$SPEC" ] && echo true || echo false)"
assert_contains "spec references t-2991" "t-2991" "$SPEC"
assert_contains "spec documents the budget fix" "context-budget.sh" "$SPEC"

# ── Test 7 (t-4): v2 — chooser, diagram-type cookbook, checker, escalation ──
echo "Test 7: v2 coverage"
assert_contains "question→diagram chooser" "## Choose the diagram" "$SKILL"
for kind in "Sequence" "State machine" "Data flow" "Swimlane" "Decision table" "Causal loop" "Entity-relationship" "Dependency graph"; do
    assert_contains "cookbook covers $kind" "### .*$kind" "$SKILL"
done
assert_contains "checker referenced" "check.py" "$SKILL"
assert "check.py exists" "true" "$([ -f "$REPO_ROOT/system/skills/terminal-diagrams/check.py" ] && echo true || echo false)"
assert_contains "escalation to artifact-diagramming" "artifact-diagramming" "$SKILL"
CHECK_OUT="$(python3 "$REPO_ROOT/system/skills/terminal-diagrams/check.py" "$SKILL" 2>&1)"
assert "every diagram in SKILL.md passes check.py" "0" "$?"
[ -n "$CHECK_OUT" ] && echo "$CHECK_OUT" | head -5
assert "no duplicated trailing lines" "1" "$(grep -c "faster than the prose it replaces" "$SKILL")"

# ── Test 8 (t-4): examples are project- and domain-agnostic ──
echo "Test 8: no project or domain specifics in examples"
# Generic leak shapes only; private names never live in this public repo. Add them locally
# via BRANA_PRIVATE_TERMS="term1|term2" (extended regex, case-insensitive).
LEAK_RE='\bt-[0-9]{2,}\b|clients/|epic-[a-z]'
[ -n "${BRANA_PRIVATE_TERMS:-}" ] && LEAK_RE="$LEAK_RE|$BRANA_PRIVATE_TERMS"
LEAKS=$(grep -ciE "$LEAK_RE" "$SKILL" || true)
assert "no task IDs, client paths or private terms in SKILL.md" "0" "${LEAKS:-0}"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
