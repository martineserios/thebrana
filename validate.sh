#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_DIR="$SCRIPT_DIR/system"
ERRORS=0
WARNINGS=0

echo "=== Brana Validate ==="
echo ""

fail() { echo "  FAIL: $1"; ((ERRORS++)); }
warn() { echo "  WARN: $1"; ((WARNINGS++)); }
pass() { echo "  PASS: $1"; }

# Check 1: Skill YAML frontmatter
echo "Checking skill frontmatter..."
for skill_dir in "$SYSTEM_DIR"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    skill_file="$skill_dir/SKILL.md"

    if [ ! -f "$skill_file" ]; then
        fail "Missing SKILL.md in skills/$skill_name/"
        continue
    fi

    # Extract and validate YAML frontmatter
    frontmatter=$(sed -n '/^---$/,/^---$/p' "$skill_file" | sed '1d;$d')
    if [ -z "$frontmatter" ]; then
        fail "No YAML frontmatter in skills/$skill_name/SKILL.md"
        continue
    fi

    if ! echo "$frontmatter" | python3 -c "import sys, yaml; yaml.safe_load(sys.stdin)" 2>/dev/null; then
        fail "Invalid YAML in skills/$skill_name/SKILL.md"
        continue
    fi

    # Check name field matches directory
    yaml_name=$(echo "$frontmatter" | python3 -c "import sys, yaml; d=yaml.safe_load(sys.stdin); print(d.get('name',''))")
    if [ "$yaml_name" != "$skill_name" ]; then
        fail "Skill name mismatch: dir=$skill_name, yaml=$yaml_name"
    else
        pass "skills/$skill_name/ — valid frontmatter, name matches"
    fi
done
echo ""

# Check 2: Rule files (frontmatter optional)
echo "Checking rules..."
for rule_file in "$SYSTEM_DIR"/rules/*.md; do
    rule_name=$(basename "$rule_file")
    if head -1 "$rule_file" | grep -q '^---$'; then
        frontmatter=$(sed -n '/^---$/,/^---$/p' "$rule_file" | sed '1d;$d')
        if ! echo "$frontmatter" | python3 -c "import sys, yaml; yaml.safe_load(sys.stdin)" 2>/dev/null; then
            fail "Invalid YAML frontmatter in rules/$rule_name"
        else
            pass "rules/$rule_name — valid frontmatter"
        fi
    else
        pass "rules/$rule_name — no frontmatter (loads unconditionally)"
    fi
done
echo ""

# Check 3: JSON validity
echo "Checking JSON files..."
if jq . "$SYSTEM_DIR/settings.json" > /dev/null 2>&1; then
    pass "settings.json — valid JSON"
else
    fail "settings.json — invalid JSON"
fi
echo ""

# Check 4: Agent frontmatter
echo "Checking agents..."
for agent_file in "$SYSTEM_DIR"/agents/*.md; do
    agent_name=$(basename "$agent_file" .md)
    frontmatter=$(sed -n '/^---$/,/^---$/p' "$agent_file" | sed '1d;$d')
    if [ -z "$frontmatter" ]; then
        fail "No YAML frontmatter in agents/$agent_name.md"
        continue
    fi

    has_name=$(echo "$frontmatter" | python3 -c "import sys, yaml; d=yaml.safe_load(sys.stdin); print('yes' if d.get('name') else 'no')")
    has_desc=$(echo "$frontmatter" | python3 -c "import sys, yaml; d=yaml.safe_load(sys.stdin); print('yes' if d.get('description') else 'no')")

    if [ "$has_name" != "yes" ]; then fail "agents/$agent_name.md missing 'name' field"; fi
    if [ "$has_desc" != "yes" ]; then fail "agents/$agent_name.md missing 'description' field"; fi
    if [ "$has_name" = "yes" ] && [ "$has_desc" = "yes" ]; then
        pass "agents/$agent_name.md — valid frontmatter"
    fi
done
echo ""

# Check 5: Context budget
echo "Checking context budget..."
BUDGET=0

# CLAUDE.md (always loaded)
if [ -f "$SYSTEM_DIR/CLAUDE.md" ]; then
    SIZE=$(wc -c < "$SYSTEM_DIR/CLAUDE.md")
    BUDGET=$((BUDGET + SIZE))
    echo "  CLAUDE.md: ${SIZE} bytes"
fi

# Rules without paths: field (always loaded)
for rule_file in "$SYSTEM_DIR"/rules/*.md; do
    if ! grep -q '^paths:' "$rule_file" 2>/dev/null; then
        SIZE=$(wc -c < "$rule_file")
        BUDGET=$((BUDGET + SIZE))
        echo "  $(basename "$rule_file"): ${SIZE} bytes (always loaded)"
    fi
done

# Skill descriptions (just the description line from frontmatter)
for skill_dir in "$SYSTEM_DIR"/skills/*/; do
    skill_file="$skill_dir/SKILL.md"
    if [ -f "$skill_file" ]; then
        DESC_SIZE=$(grep '^description:' "$skill_file" | wc -c)
        BUDGET=$((BUDGET + DESC_SIZE))
    fi
done

echo "  Total always-loaded: ${BUDGET} bytes"
if [ "$BUDGET" -gt 15360 ]; then
    fail "Context budget exceeds 15KB (${BUDGET} bytes > 15360 bytes)"
else
    pass "Context budget OK (${BUDGET}/15360 bytes)"
fi
echo ""

# Check 6: No secrets
echo "Checking for secrets..."
SECRETS_FOUND=$(grep -rn -E '(API_KEY|SECRET|PASSWORD|TOKEN|PRIVATE_KEY)\s*=' "$SYSTEM_DIR" 2>/dev/null | grep -v -E '(\.sh:|#|example|placeholder|never commit)' || true)
if [ -n "$SECRETS_FOUND" ]; then
    fail "Potential secrets found:"
    echo "$SECRETS_FOUND"
else
    pass "No secrets detected"
fi
echo ""

# Check 7: Duplicate skill names
echo "Checking for duplicate skill names..."
SKILL_NAMES=$(for f in "$SYSTEM_DIR"/skills/*/SKILL.md; do
    sed -n '/^---$/,/^---$/p' "$f" | grep '^name:' | sed 's/name: *//'
done | sort)
DUPES=$(echo "$SKILL_NAMES" | uniq -d)
if [ -n "$DUPES" ]; then
    fail "Duplicate skill names: $DUPES"
else
    pass "No duplicate skill names"
fi
echo ""

# Check 8: File size sanity
echo "Checking file sizes..."
OVERSIZED=$(find "$SYSTEM_DIR" -type f -size +50k 2>/dev/null)
if [ -n "$OVERSIZED" ]; then
    fail "Files over 50KB found:"
    echo "$OVERSIZED"
else
    pass "All files under 50KB"
fi
echo ""

# Summary
echo "=== Validation Summary ==="
echo "Errors: $ERRORS"
echo "Warnings: $WARNINGS"
if [ "$ERRORS" -gt 0 ]; then
    echo "VALIDATION FAILED"
    exit 1
else
    echo "VALIDATION PASSED"
    exit 0
fi
