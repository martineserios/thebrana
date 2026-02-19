#!/usr/bin/env bash
set -euo pipefail

# Brana pre-commit hook for thebrana repo.
# Runs a fast subset of validate.sh checks on staged files.
# Install: cp pre-commit.sh .git/hooks/pre-commit

REPO_ROOT="$(git rev-parse --show-toplevel)"
SYSTEM_DIR="$REPO_ROOT/system"
ERRORS=0

fail() { echo "pre-commit FAIL: $1"; ((ERRORS++)); }

# Get staged files
STAGED=$(git diff --cached --name-only --diff-filter=ACM)
if [ -z "$STAGED" ]; then exit 0; fi

# Check 1: Skill frontmatter on staged SKILL.md files
for f in $STAGED; do
    case "$f" in system/skills/*/SKILL.md)
        skill_name=$(basename "$(dirname "$f")")
        frontmatter=$(awk 'NR==1 && /^---$/{in_fm=1; next} in_fm && /^---$/{exit} in_fm{print}' "$REPO_ROOT/$f")
        if [ -z "$frontmatter" ]; then
            fail "No YAML frontmatter in $f"
            continue
        fi
        if ! echo "$frontmatter" | python3 -c "import sys, yaml; yaml.safe_load(sys.stdin)" 2>/dev/null; then
            fail "Invalid YAML in $f"
            continue
        fi
        yaml_name=$(echo "$frontmatter" | python3 -c "import sys, yaml; d=yaml.safe_load(sys.stdin); print(d.get('name',''))")
        if [ "$yaml_name" != "$skill_name" ]; then
            fail "Skill name mismatch in $f: dir=$skill_name, yaml=$yaml_name"
        fi
    ;; esac
done

# Check 2: Agent frontmatter on staged agent files
for f in $STAGED; do
    case "$f" in system/agents/*.md)
        frontmatter=$(awk 'NR==1 && /^---$/{in_fm=1; next} in_fm && /^---$/{exit} in_fm{print}' "$REPO_ROOT/$f")
        if [ -z "$frontmatter" ]; then
            fail "No YAML frontmatter in $f"
            continue
        fi
        has_name=$(echo "$frontmatter" | python3 -c "import sys, yaml; d=yaml.safe_load(sys.stdin); print('yes' if d.get('name') else 'no')")
        has_desc=$(echo "$frontmatter" | python3 -c "import sys, yaml; d=yaml.safe_load(sys.stdin); print('yes' if d.get('description') else 'no')")
        if [ "$has_name" != "yes" ]; then fail "$f missing 'name' field"; fi
        if [ "$has_desc" != "yes" ]; then fail "$f missing 'description' field"; fi
    ;; esac
done

# Check 3: Hook script syntax on staged .sh files
for f in $STAGED; do
    case "$f" in system/hooks/*.sh)
        if ! bash -n "$REPO_ROOT/$f" 2>/dev/null; then
            fail "Syntax error in $f"
        fi
    ;; esac
done

# Check 4: settings.json validity
for f in $STAGED; do
    case "$f" in system/settings.json)
        if ! jq . "$REPO_ROOT/$f" > /dev/null 2>&1; then
            fail "Invalid JSON in $f"
        fi
    ;; esac
done

# Check 5: Secrets in staged files
for f in $STAGED; do
    HITS=$(git show ":$f" 2>/dev/null | grep -nE '(API_KEY|SECRET|PASSWORD|TOKEN|PRIVATE_KEY)\s*=' 2>/dev/null | grep -v -E '(#|example|placeholder|never commit)' || true)
    if [ -n "$HITS" ]; then
        fail "Potential secret in $f: $HITS"
    fi
done

# Check 6: Context budget (always run if any always-loaded file is staged)
BUDGET_FILES="system/CLAUDE.md system/rules/ system/skills/ system/agents/"
NEEDS_BUDGET=false
for f in $STAGED; do
    for prefix in $BUDGET_FILES; do
        case "$f" in $prefix*) NEEDS_BUDGET=true; break ;; esac
    done
done

if [ "$NEEDS_BUDGET" = true ]; then
    BUDGET=0
    if [ -f "$SYSTEM_DIR/CLAUDE.md" ]; then
        BUDGET=$((BUDGET + $(wc -c < "$SYSTEM_DIR/CLAUDE.md")))
    fi
    for rule_file in "$SYSTEM_DIR"/rules/*.md; do
        if ! grep -q '^paths:' "$rule_file" 2>/dev/null; then
            BUDGET=$((BUDGET + $(wc -c < "$rule_file")))
        fi
    done
    for skill_dir in "$SYSTEM_DIR"/skills/*/; do
        skill_file="$skill_dir/SKILL.md"
        if [ -f "$skill_file" ]; then
            BUDGET=$((BUDGET + $(grep '^description:' "$skill_file" | wc -c)))
        fi
    done
    for agent_file in "$SYSTEM_DIR"/agents/*.md; do
        if [ -f "$agent_file" ]; then
            BUDGET=$((BUDGET + $(sed -n '/^---$/,/^---$/p' "$agent_file" | grep '^description:' | wc -c)))
        fi
    done
    if [ "$BUDGET" -gt 24576 ]; then
        fail "Context budget exceeds 24KB (${BUDGET} bytes > 24576)"
    fi
fi

if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo "Pre-commit: $ERRORS error(s). Fix before committing."
    exit 1
fi
