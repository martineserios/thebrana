#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_DIR="$SCRIPT_DIR/system"
TARGET_DIR="$HOME/.claude"

echo "=== Brana Deploy ==="
echo "Source: $SYSTEM_DIR"
echo "Target: $TARGET_DIR"
echo ""

# Step 1: Validate first
echo "Running validation..."
"$SCRIPT_DIR/validate.sh" || { echo "DEPLOY ABORTED: validation failed"; exit 1; }
echo ""

# Step 2: Backup existing CLAUDE.md if it has real content
if [ -f "$TARGET_DIR/CLAUDE.md" ]; then
    if ! grep -qi "intentionally blank" "$TARGET_DIR/CLAUDE.md" 2>/dev/null; then
        BACKUP="$TARGET_DIR/CLAUDE.md.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$TARGET_DIR/CLAUDE.md" "$BACKUP"
        echo "Backed up existing CLAUDE.md → $BACKUP"
    fi
fi

# Step 3: Remove brana-managed directories (clean deploy)
echo "Cleaning brana-managed directories..."
rm -rf "$TARGET_DIR/skills"
rm -rf "$TARGET_DIR/rules"
rm -rf "$TARGET_DIR/agents"

# Step 4: Copy system files
echo "Deploying files..."
cp "$SYSTEM_DIR/CLAUDE.md" "$TARGET_DIR/CLAUDE.md"
echo "  ✓ CLAUDE.md"

cp -r "$SYSTEM_DIR/skills" "$TARGET_DIR/skills"
echo "  ✓ skills/"

cp -r "$SYSTEM_DIR/rules" "$TARGET_DIR/rules"
echo "  ✓ rules/"

cp -r "$SYSTEM_DIR/agents" "$TARGET_DIR/agents"
echo "  ✓ agents/"

# Step 5: Merge settings.json (brana base + user overlay)
if [ -f "$TARGET_DIR/settings.json" ]; then
    # Additive hooks merge: brana hooks overlay user hooks, user wins for everything else.
    # Without this, user's empty hooks: {} would overwrite brana's hook configs.
    # See 24-roadmap-corrections.md error #1 for details.
    MERGED=$(jq -s '(.[0].hooks // {}) as $brana | (.[1].hooks // {}) as $user | .[0] * .[1] * {hooks: ($user * $brana)}' "$SYSTEM_DIR/settings.json" "$TARGET_DIR/settings.json")
    echo "$MERGED" > "$TARGET_DIR/settings.json"
    echo "  ✓ settings.json (merged — user settings preserved, hooks additive)"
else
    cp "$SYSTEM_DIR/settings.json" "$TARGET_DIR/settings.json"
    echo "  ✓ settings.json (new)"
fi

echo ""
echo "=== Deploy Complete ==="
echo "Deployed to: $TARGET_DIR"
echo "  - CLAUDE.md (mastermind identity)"
echo "  - $(find "$TARGET_DIR/skills" -name "SKILL.md" | wc -l) skills"
echo "  - $(find "$TARGET_DIR/rules" -name "*.md" | wc -l) rules"
echo "  - $(find "$TARGET_DIR/agents" -name "*.md" | wc -l) agents"
echo ""
echo "Start a new Claude Code session to activate changes."
