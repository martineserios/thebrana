#!/usr/bin/env bash
set -euo pipefail

# bootstrap.sh — Deploy brana identity layer to ~/.claude/
#
# The brana plugin (system/) handles: skills, agents, hooks, commands
# This script handles: CLAUDE.md, rules, scripts, scheduler, claude-flow
#
# Usage:
#   ./bootstrap.sh          Full sync (idempotent, safe to re-run)
#   ./bootstrap.sh --check  Show what would change without applying
#   ./bootstrap.sh --help   Show this help

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_DIR="$SCRIPT_DIR/system"
TARGET_DIR="$HOME/.claude"
CHECK_ONLY=false

# Parse args
case "${1:-}" in
    --check)  CHECK_ONLY=true ;;
    --help|-h)
        echo "Usage: ./bootstrap.sh [--check|--help]"
        echo ""
        echo "Deploy brana identity layer (CLAUDE.md, rules, scripts, scheduler, claude-flow)."
        echo "The brana plugin handles skills, agents, hooks, and commands."
        echo ""
        echo "Options:"
        echo "  --check  Show what would change without applying"
        echo "  --help   Show this help"
        echo ""
        echo "This script is idempotent — safe to run multiple times."
        exit 0
        ;;
    "") ;;  # no args = full sync
    *)  echo "Unknown option: $1. Use --help for usage."; exit 1 ;;
esac

echo "=== Brana Bootstrap (identity layer) ==="
echo "Source: $SYSTEM_DIR"
echo "Target: $TARGET_DIR"
if $CHECK_ONLY; then
    echo "Mode: CHECK ONLY (no changes will be applied)"
fi
echo ""

mkdir -p "$TARGET_DIR"
CHANGES=0

# --- Helper: diff and optionally copy a file ---
sync_file() {
    local src="$1" dst="$2" label="$3"
    if [ ! -f "$dst" ]; then
        CHANGES=$((CHANGES + 1))
        if $CHECK_ONLY; then
            echo "  + $label (new)"
        else
            cp "$src" "$dst"
            echo "  + $label (new)"
        fi
    elif ! diff -q "$src" "$dst" &>/dev/null; then
        CHANGES=$((CHANGES + 1))
        if $CHECK_ONLY; then
            echo "  ~ $label (changed)"
        else
            cp "$src" "$dst"
            echo "  ~ $label (updated)"
        fi
    else
        echo "  = $label (unchanged)"
    fi
}

# --- Helper: sync a directory ---
sync_dir() {
    local src="$1" dst="$2" label="$3"
    mkdir -p "$dst"
    local dir_changes=0

    # Copy/update files from source
    for f in "$src"/*; do
        [ -f "$f" ] || continue
        local fname=$(basename "$f")
        if [ ! -f "$dst/$fname" ] || ! diff -q "$f" "$dst/$fname" &>/dev/null; then
            dir_changes=$((dir_changes + 1))
            if ! $CHECK_ONLY; then
                cp "$f" "$dst/$fname"
            fi
        fi
    done

    # Remove files in dest that aren't in source (brana-managed)
    for f in "$dst"/*; do
        [ -f "$f" ] || continue
        local fname=$(basename "$f")
        if [ ! -f "$src/$fname" ]; then
            dir_changes=$((dir_changes + 1))
            if ! $CHECK_ONLY; then
                rm "$f"
            fi
        fi
    done

    CHANGES=$((CHANGES + dir_changes))
    if [ $dir_changes -gt 0 ]; then
        echo "  ~ $label ($dir_changes files changed)"
    else
        echo "  = $label (unchanged)"
    fi
}

# --- Step 1: CLAUDE.md ---
echo "Identity:"
if [ -f "$TARGET_DIR/CLAUDE.md" ] && [ ! -f "$TARGET_DIR/CLAUDE.md.bootstrap-backup" ]; then
    if ! grep -qi "intentionally blank" "$TARGET_DIR/CLAUDE.md" 2>/dev/null; then
        if ! diff -q "$SYSTEM_DIR/CLAUDE.md" "$TARGET_DIR/CLAUDE.md" &>/dev/null; then
            if ! $CHECK_ONLY; then
                cp "$TARGET_DIR/CLAUDE.md" "$TARGET_DIR/CLAUDE.md.bootstrap-backup"
                echo "  Backed up existing CLAUDE.md"
            else
                echo "  Would backup existing CLAUDE.md"
            fi
        fi
    fi
fi
sync_file "$SYSTEM_DIR/CLAUDE.md" "$TARGET_DIR/CLAUDE.md" "CLAUDE.md"

# --- Step 1b: Remove stale pre-plugin directories ---
# Skills, commands, and agents are now provided by the plugin (system/).
# Old deploy.sh copied them to ~/.claude/ — remove to prevent duplicates.
echo "Plugin migration cleanup:"
for stale_dir in skills commands agents; do
    if [ -d "$TARGET_DIR/$stale_dir" ]; then
        CHANGES=$((CHANGES + 1))
        if $CHECK_ONLY; then
            echo "  - $stale_dir/ (would remove — now provided by plugin)"
        else
            rm -rf "$TARGET_DIR/$stale_dir"
            echo "  - $stale_dir/ (removed — now provided by plugin)"
        fi
    else
        echo "  = $stale_dir/ (already clean)"
    fi
done

# --- Step 2: Rules ---
echo "Rules:"
sync_dir "$SYSTEM_DIR/rules" "$TARGET_DIR/rules" "rules/"

# --- Step 3: Scripts ---
echo "Scripts:"
if [ -d "$SYSTEM_DIR/scripts" ]; then
    sync_dir "$SYSTEM_DIR/scripts" "$TARGET_DIR/scripts" "scripts/"
    if ! $CHECK_ONLY; then
        chmod +x "$TARGET_DIR/scripts/"*.sh 2>/dev/null || true
    fi
fi

# --- Step 4: Statusline ---
echo "Extras:"
if [ -f "$SYSTEM_DIR/statusline.sh" ]; then
    sync_file "$SYSTEM_DIR/statusline.sh" "$TARGET_DIR/statusline.sh" "statusline.sh"
    if ! $CHECK_ONLY; then
        chmod +x "$TARGET_DIR/statusline.sh" 2>/dev/null || true
    fi
fi

# --- Step 4b: Migrate hooks from settings.json ---
# Plugin handles hooks via hooks/hooks.json — remove from global settings to prevent duplicates
echo "Hook migration:"
SETTINGS_FILE="$TARGET_DIR/settings.json"
if [ -f "$SETTINGS_FILE" ] && grep -q '"hooks"' "$SETTINGS_FILE" 2>/dev/null; then
    if $CHECK_ONLY; then
        echo "  ~ settings.json (would remove hooks section — now handled by plugin)"
        CHANGES=$((CHANGES + 1))
    else
        # Use jq if available, otherwise Python, otherwise warn
        if command -v jq &>/dev/null; then
            jq 'del(.hooks)' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
            echo "  ~ settings.json (removed hooks — now handled by plugin)"
            CHANGES=$((CHANGES + 1))
        elif command -v python3 &>/dev/null; then
            python3 -c "
import json, sys
with open('$SETTINGS_FILE') as f: d = json.load(f)
d.pop('hooks', None)
with open('$SETTINGS_FILE', 'w') as f: json.dump(d, f, indent=2)
print('  ~ settings.json (removed hooks — now handled by plugin)')
" && CHANGES=$((CHANGES + 1))
        else
            echo "  ! settings.json still has hooks (install jq or python3 to auto-migrate)"
        fi
    fi
else
    echo "  = settings.json (no hooks to migrate)"
fi

# --- Step 5: Scheduler ---
echo "Scheduler:"
SCHED_SRC="$SYSTEM_DIR/scheduler"
SCHED_DIR="$TARGET_DIR/scheduler"
if [ -d "$SCHED_SRC" ]; then
    if ! $CHECK_ONLY; then
        mkdir -p "$SCHED_DIR/logs" "$SCHED_DIR/locks" "$SCHED_DIR/templates"
    fi

    # Scheduler scripts (always overwrite — brana-managed)
    for script in brana-scheduler brana-scheduler-runner.sh brana-scheduler-notify.sh check-agentdb-integration.sh; do
        if [ -f "$SCHED_SRC/$script" ]; then
            sync_file "$SCHED_SRC/$script" "$SCHED_DIR/$script" "scheduler/$script"
            if ! $CHECK_ONLY; then
                chmod +x "$SCHED_DIR/$script" 2>/dev/null || true
            fi
        fi
    done

    # Templates (always overwrite)
    if [ -d "$SCHED_SRC/templates" ]; then
        for t in "$SCHED_SRC/templates/"*; do
            [ -f "$t" ] || continue
            local_name=$(basename "$t")
            sync_file "$t" "$SCHED_DIR/templates/$local_name" "scheduler/templates/$local_name"
        done
    fi

    # Config template — only if user config doesn't exist
    if [ ! -f "$SCHED_DIR/scheduler.json" ] && [ -f "$SCHED_SRC/scheduler.template.json" ]; then
        CHANGES=$((CHANGES + 1))
        if ! $CHECK_ONLY; then
            cp "$SCHED_SRC/scheduler.template.json" "$SCHED_DIR/scheduler.json"
            echo "  + scheduler/scheduler.json (new — edit then run: brana-scheduler deploy)"
        else
            echo "  + scheduler/scheduler.json (would create from template)"
        fi
    fi

    # PATH symlink
    if ! $CHECK_ONLY; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$SCHED_DIR/brana-scheduler" "$HOME/.local/bin/brana-scheduler"
    fi
    echo "  = brana-scheduler on PATH"
else
    echo "  — scheduler/ (not found in source)"
fi

# --- Step 6: claude-flow runtime ---
echo "claude-flow:"
CF_BIN=""
for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
    [ -x "$candidate" ] && CF_BIN="$candidate" && break
done

if [ -n "$CF_BIN" ]; then
    CF_PKG_DIR="$(dirname "$CF_BIN")/../lib/node_modules/claude-flow"

    # sql.js dependency
    if [ -d "$CF_PKG_DIR" ] && [ ! -d "$CF_PKG_DIR/node_modules/sql.js" ]; then
        CHANGES=$((CHANGES + 1))
        if ! $CHECK_ONLY; then
            echo "  Installing sql.js..."
            npm install sql.js --prefix "$CF_PKG_DIR" --silent 2>/dev/null && echo "  + sql.js" || echo "  ! sql.js install failed"
        else
            echo "  + sql.js (would install)"
        fi
    else
        echo "  = sql.js present"
    fi

    # Embeddings config
    mkdir -p "$HOME/.claude-flow"
    if [ -f "$SCRIPT_DIR/.claude-flow/embeddings.json" ]; then
        sync_file "$SCRIPT_DIR/.claude-flow/embeddings.json" "$HOME/.claude-flow/embeddings.json" "embeddings.json"
    fi

    # ControllerRegistry shim
    CF_MEM_DIST="$CF_PKG_DIR/node_modules/@claude-flow/memory/dist"
    if [ -d "$CF_MEM_DIST" ] && [ -f "$SCRIPT_DIR/.claude-flow/controller-registry-shim.js" ]; then
        sync_file "$SCRIPT_DIR/.claude-flow/controller-registry-shim.js" "$CF_MEM_DIST/controller-registry-shim.js" "AgentDB shim"
        # Ensure index.js re-exports ControllerRegistry
        if ! $CHECK_ONLY && ! grep -q "controller-registry-shim" "$CF_MEM_DIST/index.js" 2>/dev/null; then
            sed -i '1i // ===== ControllerRegistry Shim (bridges memory-bridge.js → AgentDB v3) =====\nexport { ControllerRegistry } from '\''./controller-registry-shim.js'\'';' "$CF_MEM_DIST/index.js"
            echo "  ~ index.js patched (ControllerRegistry re-export)"
            CHANGES=$((CHANGES + 1))
        fi
    elif [ ! -d "$CF_MEM_DIST" ]; then
        echo "  — @claude-flow/memory not installed (basic fallback)"
    fi
else
    echo "  — claude-flow not found (Layer 0 fallback)"
fi

# --- Summary ---
echo ""
if $CHECK_ONLY; then
    if [ $CHANGES -gt 0 ]; then
        echo "=== $CHANGES change(s) detected. Run without --check to apply. ==="
    else
        echo "=== Everything up to date. ==="
    fi
else
    echo "=== Bootstrap Complete ($CHANGES change(s)) ==="
    echo ""
    echo "Identity layer deployed to: $TARGET_DIR"
    echo "  - CLAUDE.md (mastermind identity)"
    echo "  - $(find "$TARGET_DIR/rules" -name "*.md" 2>/dev/null | wc -l) rules"
    if [ -d "$TARGET_DIR/scripts" ]; then
        echo "  - $(find "$TARGET_DIR/scripts" -name "*.sh" 2>/dev/null | wc -l) scripts"
    fi
    if [ -d "$TARGET_DIR/scheduler" ]; then
        echo "  - scheduler (brana-scheduler on PATH)"
    fi
    echo ""
    echo "Plugin (skills, agents, hooks) loaded via:"
    echo "  Dev:  claude --plugin-dir ./system"
    echo "  Prod: claude plugin install brana"
    echo ""
    echo "Start a new Claude Code session to activate."
fi
