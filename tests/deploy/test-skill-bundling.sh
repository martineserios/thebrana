#!/usr/bin/env bash
# Tests for ADR-011: Skills Bundling
# Validates that skill scripts are bundled, valid, referenced correctly,
# and backward-compatible with system/scripts/ originals.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0

assert_outcome() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label — expected '$expected', got '$actual'"
    fi
}

# ═══════════════════════════════════════════════════════════════
# SECTION 1: Source scripts exist in skill directory
# ═══════════════════════════════════════════════════════════════

echo "=== Bundled scripts exist in system/skills/knowledge/ ==="

SKILL_DIR="$REPO_DIR/system/skills/knowledge"

if [ -f "$SKILL_DIR/index-knowledge.sh" ]; then
    assert_outcome "index-knowledge.sh exists in skill dir" "true" "true"
else
    assert_outcome "index-knowledge.sh exists in skill dir" "true" "false"
fi

if [ -f "$SKILL_DIR/generate-index.sh" ]; then
    assert_outcome "generate-index.sh exists in skill dir" "true" "true"
else
    assert_outcome "generate-index.sh exists in skill dir" "true" "false"
fi

# ═══════════════════════════════════════════════════════════════
# SECTION 2: Scripts pass bash -n syntax validation
# ═══════════════════════════════════════════════════════════════

echo ""
echo "=== Scripts are valid bash ==="

if bash -n "$SKILL_DIR/index-knowledge.sh" 2>/dev/null; then
    assert_outcome "index-knowledge.sh passes bash -n" "true" "true"
else
    assert_outcome "index-knowledge.sh passes bash -n" "true" "false"
fi

if bash -n "$SKILL_DIR/generate-index.sh" 2>/dev/null; then
    assert_outcome "generate-index.sh passes bash -n" "true" "true"
else
    assert_outcome "generate-index.sh passes bash -n" "true" "false"
fi

# ═══════════════════════════════════════════════════════════════
# SECTION 3: SKILL.md references deployed paths
# ═══════════════════════════════════════════════════════════════

echo ""
echo "=== SKILL.md references deployed skill paths ==="

SKILL_MD="$SKILL_DIR/SKILL.md"

if grep -q 'skills/knowledge/index-knowledge.sh' "$SKILL_MD" 2>/dev/null; then
    assert_outcome "SKILL.md references skills/knowledge/index-knowledge.sh" "true" "true"
else
    assert_outcome "SKILL.md references skills/knowledge/index-knowledge.sh" "true" "false"
fi

if grep -q 'skills/knowledge/generate-index.sh' "$SKILL_MD" 2>/dev/null; then
    assert_outcome "SKILL.md references skills/knowledge/generate-index.sh" "true" "true"
else
    assert_outcome "SKILL.md references skills/knowledge/generate-index.sh" "true" "false"
fi

# ═══════════════════════════════════════════════════════════════
# SECTION 4: deploy.sh contains chmod +x for skill scripts
# ═══════════════════════════════════════════════════════════════

echo ""
echo "=== deploy.sh has chmod +x for skill scripts ==="

DEPLOY="$REPO_DIR/deploy.sh"

if grep -q 'find.*skills.*chmod' "$DEPLOY" 2>/dev/null; then
    assert_outcome "deploy.sh has find+chmod for skill scripts" "true" "true"
else
    assert_outcome "deploy.sh has find+chmod for skill scripts" "true" "false"
fi

# ═══════════════════════════════════════════════════════════════
# SECTION 5: Backward compat — originals still exist in scripts/
# ═══════════════════════════════════════════════════════════════

echo ""
echo "=== Backward compat: system/scripts/ originals exist ==="

SCRIPTS_DIR="$REPO_DIR/system/scripts"

if [ -f "$SCRIPTS_DIR/index-knowledge.sh" ]; then
    assert_outcome "system/scripts/index-knowledge.sh still exists" "true" "true"
else
    assert_outcome "system/scripts/index-knowledge.sh still exists" "true" "false"
fi

if [ -f "$SCRIPTS_DIR/generate-index.sh" ]; then
    assert_outcome "system/scripts/generate-index.sh still exists" "true" "true"
else
    assert_outcome "system/scripts/generate-index.sh still exists" "true" "false"
fi

# ═══════════════════════════════════════════════════════════════
# SECTION 6: Deprecation headers in originals
# ═══════════════════════════════════════════════════════════════

echo ""
echo "=== Deprecation headers in system/scripts/ originals ==="

if grep -q 'DEPRECATED' "$SCRIPTS_DIR/index-knowledge.sh" 2>/dev/null; then
    assert_outcome "index-knowledge.sh has DEPRECATED header" "true" "true"
else
    assert_outcome "index-knowledge.sh has DEPRECATED header" "true" "false"
fi

if grep -q 'DEPRECATED' "$SCRIPTS_DIR/generate-index.sh" 2>/dev/null; then
    assert_outcome "generate-index.sh has DEPRECATED header" "true" "true"
else
    assert_outcome "generate-index.sh has DEPRECATED header" "true" "false"
fi

# ═══════════════════════════════════════════════════════════════
# Results
# ═══════════════════════════════════════════════════════════════

echo ""
echo "==============================================="
echo "Results: $PASS passed, $FAIL failed"
echo "==============================================="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
