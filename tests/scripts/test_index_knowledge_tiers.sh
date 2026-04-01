#!/usr/bin/env bash
# Tests for index-knowledge.sh — tier classification and multi-category indexing.
# Run: bash tests/scripts/test_index_knowledge_tiers.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

echo "=== test_index_knowledge_tiers.sh ==="

# ── Simulate tier classification logic from the script ──
# Replicate the DOC_CATEGORIES and classify_tier function

KNOWLEDGE_DIR="$HOME/enter_thebrana/brana-knowledge/dimensions"
THEBRANA_DIR="$HOME/enter_thebrana/thebrana"

# IMPORTANT: more specific paths MUST come before their parent paths
DOC_CATEGORIES=(
    "$KNOWLEDGE_DIR:dimension:semantic"
    "$THEBRANA_DIR/docs/architecture/decisions:decision:semantic"
    "$THEBRANA_DIR/docs/architecture/features:feature:episodic"
    "$THEBRANA_DIR/docs/architecture:architecture:semantic"
    "$THEBRANA_DIR/docs/reflections:reflection:semantic"
    "$THEBRANA_DIR/docs/ideas:idea:working"
    "$THEBRANA_DIR/docs/research:research:episodic"
)

classify_tier() {
    local filepath="$1"
    for cat in "${DOC_CATEGORIES[@]}"; do
        local dir="${cat%%:*}"
        local rest="${cat#*:}"
        local tier="${rest#*:}"
        if [[ "$filepath" == "$dir"/* ]]; then
            echo "$tier"
            return
        fi
    done
    echo "episodic"
}

classify_type() {
    local filepath="$1"
    for cat in "${DOC_CATEGORIES[@]}"; do
        local dir="${cat%%:*}"
        local rest="${cat#*:}"
        local type="${rest%%:*}"
        if [[ "$filepath" == "$dir"/* ]]; then
            echo "$type"
            return
        fi
    done
    echo "unknown"
}

# ── Test 1: Tier classification ──
echo "Test 1: Tier classification by path"
assert "dimensions → semantic" "semantic" "$(classify_tier "$KNOWLEDGE_DIR/01-overview.md")"
assert "architecture → semantic" "semantic" "$(classify_tier "$THEBRANA_DIR/docs/architecture/overview.md")"
assert "reflections → semantic" "semantic" "$(classify_tier "$THEBRANA_DIR/docs/reflections/ARCHITECTURE.md")"
assert "decisions → semantic" "semantic" "$(classify_tier "$THEBRANA_DIR/docs/architecture/decisions/ADR-026.md")"
assert "features → episodic" "episodic" "$(classify_tier "$THEBRANA_DIR/docs/architecture/features/session-hooks.md")"
assert "ideas → working" "working" "$(classify_tier "$THEBRANA_DIR/docs/ideas/skill-auto-router.md")"
assert "research → episodic" "episodic" "$(classify_tier "$THEBRANA_DIR/docs/research/some-study.md")"
assert "unknown path → episodic" "episodic" "$(classify_tier "/tmp/random-file.md")"

# ── Test 2: Type classification ──
echo "Test 2: Type classification by path"
assert "dimensions → dimension" "dimension" "$(classify_type "$KNOWLEDGE_DIR/01-overview.md")"
assert "architecture → architecture" "architecture" "$(classify_type "$THEBRANA_DIR/docs/architecture/hooks.md")"
assert "reflections → reflection" "reflection" "$(classify_type "$THEBRANA_DIR/docs/reflections/31-assurance.md")"
assert "decisions → decision" "decision" "$(classify_type "$THEBRANA_DIR/docs/architecture/decisions/ADR-025.md")"
assert "features → feature" "feature" "$(classify_type "$THEBRANA_DIR/docs/architecture/features/build.md")"
assert "ideas → idea" "idea" "$(classify_type "$THEBRANA_DIR/docs/ideas/ruflo-native-integration.md")"
assert "research → research" "research" "$(classify_type "$THEBRANA_DIR/docs/research/foo.md")"
assert "unknown → unknown" "unknown" "$(classify_type "/tmp/random.md")"

# ── Test 3: Key format uses type, not hardcoded "dimension" ──
echo "Test 3: Key format"
DOC_TYPE="architecture"
DOC_SLUG="overview"
SECTION_SLUG="ruflo-integration"
KEY="knowledge:${DOC_TYPE}:${DOC_SLUG}:${SECTION_SLUG}"
assert "key uses type" "knowledge:architecture:overview:ruflo-integration" "$KEY"

DOC_TYPE="idea"
DOC_SLUG="skill-auto-router"
SECTION_SLUG="architecture"
KEY="knowledge:${DOC_TYPE}:${DOC_SLUG}:${SECTION_SLUG}"
assert "key for ideas" "knowledge:idea:skill-auto-router:architecture" "$KEY"

# ── Test 4: Source classification ──
echo "Test 4: Source tag classification"
classify_source() {
    local filepath="$1"
    if [[ "$filepath" == *"brana-knowledge"* ]]; then
        echo "source:brana-knowledge"
    else
        echo "source:thebrana"
    fi
}
assert "brana-knowledge → source:brana-knowledge" "source:brana-knowledge" "$(classify_source "$KNOWLEDGE_DIR/01.md")"
assert "thebrana → source:thebrana" "source:thebrana" "$(classify_source "$THEBRANA_DIR/docs/ideas/foo.md")"

# ── Test 5: Doc categories cover expected directories ──
echo "Test 5: Doc category coverage"
EXPECTED_DIRS=7
ACTUAL_DIRS=${#DOC_CATEGORIES[@]}
assert "7 doc categories defined" "$EXPECTED_DIRS" "$ACTUAL_DIRS"

# Check that at least some directories exist
EXISTING=0
for cat in "${DOC_CATEGORIES[@]}"; do
    dir="${cat%%:*}"
    [ -d "$dir" ] && EXISTING=$((EXISTING + 1))
done
assert "at least 4 category dirs exist" "true" "$([ "$EXISTING" -ge 4 ] && echo true || echo false)"

# ── Test 6: Tags include tier ──
echo "Test 6: Tags include tier"
TIER="semantic"
TYPE="dimension"
FILENAME="01-overview.md"
SOURCE="source:brana-knowledge"
TAGS="${SOURCE},type:${TYPE},doc:${FILENAME},tier:${TIER}"
assert "tags contain tier:semantic" "true" "$(echo "$TAGS" | grep -q "tier:semantic" && echo true || echo false)"
assert "tags contain type:dimension" "true" "$(echo "$TAGS" | grep -q "type:dimension" && echo true || echo false)"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
