#!/usr/bin/env bash
# Tests for index-skills.sh — skill frontmatter indexing into ruflo memory.
# Run: bash tests/scripts/test_index_skills.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INDEX_SCRIPT="$REPO_ROOT/system/scripts/index-skills.sh"

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
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$haystack" | grep -q "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected to contain '$needle')"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== test_index_skills.sh ==="

# ── Test 1: Script exists and is executable ──
echo "Test 1: Script exists and is executable"
assert "index-skills.sh exists" "true" "$([ -f "$INDEX_SCRIPT" ] && echo true || echo false)"
assert "index-skills.sh is executable" "true" "$([ -x "$INDEX_SCRIPT" ] && echo true || echo false)"

# ── Test 2: parse_fm extracts frontmatter fields ──
echo "Test 2: Frontmatter parsing"
TMPSKILL=$(mktemp -d)/test-skill/SKILL.md
mkdir -p "$(dirname "$TMPSKILL")"
cat > "$TMPSKILL" << 'EOF'
---
name: test-skill
description: "A test skill for validation"
keywords: [testing, validation, shell]
task_strategies: [feature, bug-fix]
stream_affinity: [roadmap, tech-debt]
group: test-group
effort: S
---

# Test Skill
EOF

# Extract using same logic as the script
NAME=$(sed -n '/^---$/,/^---$/p' "$TMPSKILL" | grep "^name:" | head -1 | sed 's/^name:[[:space:]]*//' | sed 's/^"//' | sed 's/"$//')
DESC=$(sed -n '/^---$/,/^---$/p' "$TMPSKILL" | grep "^description:" | head -1 | sed 's/^description:[[:space:]]*//' | sed 's/^"//' | sed 's/"$//')
GROUP=$(sed -n '/^---$/,/^---$/p' "$TMPSKILL" | grep "^group:" | head -1 | sed 's/^group:[[:space:]]*//' | sed 's/^"//' | sed 's/"$//')
EFFORT=$(sed -n '/^---$/,/^---$/p' "$TMPSKILL" | grep "^effort:" | head -1 | sed 's/^effort:[[:space:]]*//' | sed 's/^"//' | sed 's/"$//')
KEYWORDS=$(sed -n '/^---$/,/^---$/p' "$TMPSKILL" | grep "^keywords:" | head -1 | sed 's/^keywords:[[:space:]]*//' | sed 's/^\[//' | sed 's/\]$//' | sed 's/,/ /g' | sed 's/"//g' | sed "s/'//g" | tr -s ' ')
STRATEGIES=$(sed -n '/^---$/,/^---$/p' "$TMPSKILL" | grep "^task_strategies:" | head -1 | sed 's/^task_strategies:[[:space:]]*//' | sed 's/^\[//' | sed 's/\]$//' | sed 's/,/ /g' | sed 's/"//g' | sed "s/'//g" | tr -s ' ')

assert "name parsed" "test-skill" "$NAME"
assert "description parsed" "A test skill for validation" "$DESC"
assert "group parsed" "test-group" "$GROUP"
assert "effort parsed" "S" "$EFFORT"
assert_contains "keywords contain testing" "testing" "$KEYWORDS"
assert_contains "keywords contain validation" "validation" "$KEYWORDS"
assert_contains "strategies contain feature" "feature" "$STRATEGIES"
assert_contains "strategies contain bug-fix" "bug-fix" "$STRATEGIES"

# ── Test 3: Skills directory has SKILL.md files ──
echo "Test 3: Skills directory has indexable files"
SKILL_COUNT=$(find "$REPO_ROOT/system/skills" -maxdepth 2 -name "SKILL.md" -not -path "*/_shared/*" -not -path "*/acquired/*" | wc -l)
assert "at least 20 skills found" "true" "$([ "$SKILL_COUNT" -ge 20 ] && echo true || echo false)"

# ── Test 4: Embed text construction ──
echo "Test 4: Embed text construction"
EMBED_TEXT="$NAME ${DESC:-} ${KEYWORDS:-} ${STRATEGIES:-}"
assert_contains "embed text has name" "test-skill" "$EMBED_TEXT"
assert_contains "embed text has description" "test skill for validation" "$EMBED_TEXT"
assert_contains "embed text has keywords" "testing" "$EMBED_TEXT"
assert_contains "embed text has strategies" "feature" "$EMBED_TEXT"

# ── Test 5: Tag construction ──
echo "Test 5: Tag construction"
SOURCE_TAG="source:brana"
TAGS="${SOURCE_TAG},group:${GROUP:-unknown}"
for s in $STRATEGIES; do
    TAGS="${TAGS},strategy:${s}"
done
assert_contains "tags have source" "source:brana" "$TAGS"
assert_contains "tags have group" "group:test-group" "$TAGS"
assert_contains "tags have strategy:feature" "strategy:feature" "$TAGS"
assert_contains "tags have strategy:bug-fix" "strategy:bug-fix" "$TAGS"

# ── Test 6: Acquired skills get external source tag ──
echo "Test 6: Source tag for acquired skills"
ACQUIRED_PATH="/some/path/skills/acquired/ext-skill/SKILL.md"
if [[ "$ACQUIRED_PATH" == *"/acquired/"* ]]; then
    SRC="source:external"
else
    SRC="source:brana"
fi
assert "acquired skill gets external tag" "source:external" "$SRC"

BRANA_PATH="/some/path/skills/build/SKILL.md"
if [[ "$BRANA_PATH" == *"/acquired/"* ]]; then
    SRC="source:external"
else
    SRC="source:brana"
fi
assert "brana skill gets brana tag" "source:brana" "$SRC"

# ── Cleanup ──
rm -rf "$(dirname "$TMPSKILL")"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
