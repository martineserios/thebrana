#!/usr/bin/env bash
# verify-counts.sh — Check doc-claimed counts against filesystem reality
# Run after deploy or manually. Warns on mismatch, never blocks.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYSTEM_DIR="$REPO_DIR/system"
DOCS_DIR="$REPO_DIR/docs"
KNOWLEDGE_DIR="$HOME/enter_thebrana/brana-knowledge/dimensions"
TARGET_DIR="$HOME/.claude"

errors=0
warnings=0

check() {
    local label="$1" actual="$2" doc_file="$3" pattern="$4"
    if [ ! -f "$doc_file" ]; then return; fi
    local claimed
    claimed=$(grep -oP "$pattern" "$doc_file" 2>/dev/null | head -1)
    if [ -z "$claimed" ]; then return; fi
    if [ "$actual" != "$claimed" ]; then
        echo "  ✗ $label: docs say $claimed, actual $actual ($doc_file)"
        ((errors++))
    else
        echo "  ✓ $label: $actual"
    fi
}

echo "=== Verify Counts ==="

# Skills count
actual_skills=$(find "$SYSTEM_DIR/skills" -name "SKILL.md" 2>/dev/null | wc -l)
check "Skills" "$actual_skills" \
    "$DOCS_DIR/reflections/14-mastermind-architecture.md" \
    '(?<=All )\d+(?= deployed skills)'

# Dimension docs count
if [ -d "$KNOWLEDGE_DIR" ]; then
    actual_dims=$(find "$KNOWLEDGE_DIR" -maxdepth 1 -name "*.md" ! -name "INDEX.md" 2>/dev/null | wc -l)
    check "Dimension docs" "$actual_dims" \
        "$DOCS_DIR/reflections/14-mastermind-architecture.md" \
        '\d+(?= docs, semantically indexed)'
    check "Dimension docs (CLAUDE.md)" "$actual_dims" \
        "$REPO_DIR/.claude/CLAUDE.md" \
        '(?<=from )\d+(?= dimension docs)'
fi

# Agents count — doc 14 splits as "Haiku (N agents)" + "Opus (N agents)"
actual_agents=$(find "$SYSTEM_DIR/agents" -name "*.md" 2>/dev/null | wc -l)
doc14="$DOCS_DIR/reflections/14-mastermind-architecture.md"
if [ -f "$doc14" ]; then
    haiku_claim=$(grep -oP 'Haiku \(\K\d+' "$doc14" 2>/dev/null | head -1)
    opus_claim=$(grep -oP 'Opus \(\K\d+' "$doc14" 2>/dev/null | head -1)
    if [ -n "$haiku_claim" ] && [ -n "$opus_claim" ]; then
        claimed_total=$((haiku_claim + opus_claim))
        if [ "$actual_agents" != "$claimed_total" ]; then
            echo "  ✗ Agents: docs say $claimed_total ($haiku_claim Haiku + $opus_claim Opus), actual $actual_agents ($doc14)"
            ((errors++))
        else
            echo "  ✓ Agents: $actual_agents ($haiku_claim Haiku + $opus_claim Opus)"
        fi
    else
        echo "  ✓ Agents: $actual_agents (no doc claim to verify)"
    fi
fi

# Rules count
actual_rules=$(find "$SYSTEM_DIR/rules" -name "*.md" 2>/dev/null | wc -l)
echo "  ✓ Rules: $actual_rules (no doc claim to verify)"

# Hook types
actual_hook_types=0
if [ -f "$TARGET_DIR/settings.json" ]; then
    actual_hook_types=$(python3 -c "
import json
with open('$TARGET_DIR/settings.json') as f:
    d = json.load(f)
print(len(d.get('hooks', {})))
" 2>/dev/null || echo 0)
fi
check "Hook types" "$actual_hook_types" \
    "$DOCS_DIR/reflections/14-mastermind-architecture.md" \
    '\d+(?= hook types connect)'

# Scripts count
actual_scripts=$(find "$SYSTEM_DIR/scripts" -name "*.sh" 2>/dev/null | wc -l)
echo "  ✓ Scripts: $actual_scripts"

# Commands count
actual_commands=$(find "$SYSTEM_DIR/commands" -type f 2>/dev/null | wc -l)
echo "  ✓ Commands: $actual_commands"

# Ghost reference check — files mentioned in doc 14 tree that don't exist
ghost_check() {
    local path="$1" label="$2"
    if [ ! -e "$path" ]; then
        echo "  ✗ Ghost: $label referenced in docs but missing ($path)"
        ((errors++))
    fi
}
ghost_check "$SYSTEM_DIR/skills" "skills/"
ghost_check "$SYSTEM_DIR/agents" "agents/"
ghost_check "$SYSTEM_DIR/rules" "rules/"
ghost_check "$SYSTEM_DIR/hooks" "hooks/"
ghost_check "$SYSTEM_DIR/scripts" "scripts/"
ghost_check "$SYSTEM_DIR/commands" "commands/"

echo ""
if [ "$errors" -gt 0 ]; then
    echo "⚠ $errors count mismatches, $warnings warnings — docs may need updating"
    echo "  Run: /memory review --audit to investigate"
    exit 0  # warn, don't block
elif [ "$warnings" -gt 0 ]; then
    echo "✓ Counts verified ($warnings minor warnings)"
else
    echo "✓ All counts verified"
fi
