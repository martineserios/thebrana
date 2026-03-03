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
rm -rf "$TARGET_DIR/hooks"
rm -rf "$TARGET_DIR/scripts"

# Step 4: Copy system files
echo "Deploying files..."
cp "$SYSTEM_DIR/CLAUDE.md" "$TARGET_DIR/CLAUDE.md"
echo "  ✓ CLAUDE.md"

cp -r "$SYSTEM_DIR/skills" "$TARGET_DIR/skills"
# Make bundled skill scripts executable
find "$TARGET_DIR/skills" \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} +
echo "  ✓ skills/"

cp -r "$SYSTEM_DIR/rules" "$TARGET_DIR/rules"
echo "  ✓ rules/"

cp -r "$SYSTEM_DIR/agents" "$TARGET_DIR/agents"
echo "  ✓ agents/"

cp -r "$SYSTEM_DIR/hooks" "$TARGET_DIR/hooks"
chmod +x "$TARGET_DIR/hooks/"*.sh
echo "  ✓ hooks/"

if [ -d "$SYSTEM_DIR/scripts" ]; then
    mkdir -p "$TARGET_DIR/scripts"
    cp "$SYSTEM_DIR/scripts/"*.sh "$TARGET_DIR/scripts/"
    chmod +x "$TARGET_DIR/scripts/"*.sh
    echo "  ✓ scripts/"
fi

if [ -d "$SYSTEM_DIR/commands" ]; then
    mkdir -p "$TARGET_DIR/commands"
    cp "$SYSTEM_DIR/commands/"* "$TARGET_DIR/commands/"
    # Make shell scripts executable
    for f in "$TARGET_DIR/commands/"*; do
        [ -f "$f" ] && head -1 "$f" | grep -q '^#!' && chmod +x "$f"
    done
    echo "  ✓ commands/"
fi

# Deploy statusline (standalone file, not in a subdirectory)
if [ -f "$SYSTEM_DIR/statusline.sh" ]; then
    cp "$SYSTEM_DIR/statusline.sh" "$TARGET_DIR/statusline.sh"
    chmod +x "$TARGET_DIR/statusline.sh"
    echo "  ✓ statusline.sh"
fi

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

# Step 6: Deploy scheduler
SCHED_SRC="$SYSTEM_DIR/scheduler"
SCHED_DIR="$TARGET_DIR/scheduler"
if [ -d "$SCHED_SRC" ]; then
    mkdir -p "$SCHED_DIR/logs" "$SCHED_DIR/locks" "$SCHED_DIR/templates"

    # Copy scripts (always overwrite — brana-managed)
    cp "$SCHED_SRC/brana-scheduler" "$SCHED_DIR/brana-scheduler"
    cp "$SCHED_SRC/brana-scheduler-runner.sh" "$SCHED_DIR/brana-scheduler-runner.sh"
    cp "$SCHED_SRC/brana-scheduler-notify.sh" "$SCHED_DIR/brana-scheduler-notify.sh"
    chmod +x "$SCHED_DIR/brana-scheduler" "$SCHED_DIR/brana-scheduler-runner.sh" "$SCHED_DIR/brana-scheduler-notify.sh"

    # Copy templates (always overwrite)
    cp "$SCHED_SRC/templates/"* "$SCHED_DIR/templates/"

    # Copy config template only if user config doesn't exist yet
    if [ ! -f "$SCHED_DIR/scheduler.json" ]; then
        cp "$SCHED_SRC/scheduler.template.json" "$SCHED_DIR/scheduler.json"
        echo "  ✓ scheduler/ (new — edit scheduler.json then run: brana-scheduler deploy)"
    else
        echo "  ✓ scheduler/ (updated scripts, user config preserved)"
    fi

    # Add brana-scheduler to PATH via symlink
    mkdir -p "$HOME/.local/bin"
    ln -sf "$SCHED_DIR/brana-scheduler" "$HOME/.local/bin/brana-scheduler"
else
    echo "  — scheduler/ (not found in source, skipping)"
fi

# Step 7: claude-flow runtime setup
CF_BIN=""
for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
    [ -x "$candidate" ] && CF_BIN="$candidate" && break
done
if [ -n "$CF_BIN" ]; then
    CF_PKG_DIR="$(dirname "$CF_BIN")/../lib/node_modules/claude-flow"
    if [ -d "$CF_PKG_DIR" ] && [ ! -d "$CF_PKG_DIR/node_modules/sql.js" ]; then
        echo "Installing sql.js in claude-flow (missing dependency)..."
        npm install sql.js --prefix "$CF_PKG_DIR" --silent 2>/dev/null && echo "  ✓ sql.js installed" || echo "  ⚠ sql.js install failed (ReasoningBank will degrade to Layer 0)"
    elif [ -d "$CF_PKG_DIR/node_modules/sql.js" ]; then
        echo "  ✓ claude-flow sql.js present"
    fi
    # Deploy embeddings config (ensures 384-dim all-MiniLM-L6-v2 across all projects)
    mkdir -p "$HOME/.claude-flow"
    if [ -f "$SCRIPT_DIR/.claude-flow/embeddings.json" ]; then
        cp "$SCRIPT_DIR/.claude-flow/embeddings.json" "$HOME/.claude-flow/embeddings.json"
        echo "  ✓ embeddings config deployed (384-dim, all-MiniLM-L6-v2)"
    fi
    # Deploy ControllerRegistry shim (activates AgentDB bridge in memory-bridge.js)
    CF_MEM_DIST="$CF_PKG_DIR/node_modules/@claude-flow/memory/dist"
    if [ -d "$CF_MEM_DIST" ] && [ -f "$SCRIPT_DIR/.claude-flow/controller-registry-shim.js" ]; then
        cp "$SCRIPT_DIR/.claude-flow/controller-registry-shim.js" "$CF_MEM_DIST/controller-registry-shim.js"
        # Ensure index.js re-exports ControllerRegistry
        if ! grep -q "controller-registry-shim" "$CF_MEM_DIST/index.js" 2>/dev/null; then
            sed -i '1i // ===== ControllerRegistry Shim (bridges memory-bridge.js → AgentDB v3) =====\nexport { ControllerRegistry } from '\''./controller-registry-shim.js'\'';' "$CF_MEM_DIST/index.js"
        fi
        echo "  ✓ AgentDB bridge shim deployed (BM25 hybrid, reflexion, causal, skills)"
    elif [ ! -d "$CF_MEM_DIST" ]; then
        echo "  ⚠ @claude-flow/memory not installed (bridge inactive, basic sql.js fallback)"
    fi
else
    echo "  ⚠ claude-flow not found (ReasoningBank unavailable, Layer 0 fallback active)"
fi

# Step 8: Verify doc counts match reality
echo ""
if [ -f "$SCRIPT_DIR/system/scripts/verify-counts.sh" ]; then
    "$SCRIPT_DIR/system/scripts/verify-counts.sh"
fi

echo ""
echo "=== Deploy Complete ==="
echo "Deployed to: $TARGET_DIR"
echo "  - CLAUDE.md (mastermind identity)"
echo "  - $(find "$TARGET_DIR/skills" -name "SKILL.md" | wc -l) skills"
echo "  - $(find "$TARGET_DIR/rules" -name "*.md" | wc -l) rules"
echo "  - $(find "$TARGET_DIR/agents" -name "*.md" | wc -l) agents"
echo "  - $(find "$TARGET_DIR/hooks" -name "*.sh" | wc -l) hooks"
if [ -d "$TARGET_DIR/scripts" ]; then
    echo "  - $(find "$TARGET_DIR/scripts" -name "*.sh" | wc -l) scripts"
fi
if [ -d "$TARGET_DIR/commands" ]; then
    echo "  - $(find "$TARGET_DIR/commands" -type f | wc -l) commands"
fi
if [ -d "$TARGET_DIR/scheduler" ]; then
    echo "  - scheduler (brana-scheduler CLI on PATH)"
fi
echo ""
echo "Start a new Claude Code session to activate changes."
