#!/usr/bin/env bash
set -euo pipefail

# bootstrap.sh — Deploy brana identity layer to ~/.claude/
#
# The brana plugin (system/) handles: skills, agents, hooks, commands, rules
# This script handles: CLAUDE.md, scripts, scheduler, claude-flow
#
# Usage:
#   ./bootstrap.sh                Full sync (idempotent, safe to re-run)
#   ./bootstrap.sh --check        Show what would change without applying
#   ./bootstrap.sh --sync-plugin  Sync plugin cache with current system/
#   ./bootstrap.sh --help         Show this help

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_DIR="$SCRIPT_DIR/system"
TARGET_DIR="$HOME/.claude"
CHECK_ONLY=false

# --- Plugin cache sync (standalone operation) ---
sync_plugin_cache() {
    local system_dir="$1"
    local cache_base="$HOME/.claude/plugins/cache/brana/brana"

    # Find installed version directory
    local cache_dir=""
    for d in "$cache_base"/*/; do
        [ -d "$d" ] && cache_dir="${d%/}" && break
    done

    if [ -z "$cache_dir" ]; then
        echo "No installed brana plugin found in $cache_base"
        echo "Install with: claude plugin install brana"
        exit 1
    fi

    local version=$(basename "$cache_dir")
    echo "=== Syncing plugin cache ==="
    echo "Source:  $system_dir"
    echo "Cache:   $cache_dir (v$version)"
    echo ""

    # Dry-run diff first
    local diff_output
    diff_output=$(diff -rq "$cache_dir" "$system_dir" 2>/dev/null | grep -v ".claude-plugin" || true)

    if [ -z "$diff_output" ]; then
        echo "Plugin cache is already up to date."
        exit 0
    fi

    echo "Changes:"
    echo "$diff_output" | while IFS= read -r line; do
        echo "  $line"
    done
    echo ""

    rsync -av --delete --exclude='.claude-plugin' "$system_dir/" "$cache_dir/" > /dev/null
    echo "Plugin cache synced. Restart Claude Code to activate."
}

# Parse args
case "${1:-}" in
    --check)  CHECK_ONLY=true ;;
    --sync-plugin)
        sync_plugin_cache "$SYSTEM_DIR"
        exit 0
        ;;
    --help|-h)
        echo "Usage: ./bootstrap.sh [--check|--sync-plugin|--help]"
        echo ""
        echo "Deploy brana identity layer (CLAUDE.md, rules, scripts, scheduler, claude-flow)."
        echo "The brana plugin handles skills, agents, hooks, and commands."
        echo ""
        echo "Options:"
        echo "  --check        Show what would change without applying"
        echo "  --sync-plugin  Sync installed plugin cache with current system/"
        echo "  --help         Show this help"
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

# --- Pre-flight: CC version check (CVE-2026-21852, CVE-2025-59536) ---
check_cc_version() {
  local ver
  ver=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if [ -z "$ver" ]; then
    echo "  ! claude binary not found or version unreadable — skipping CVE check"
    return
  fi
  local required_exfil="2.0.65"  # CVE-2026-21852 API key exfil via ANTHROPIC_BASE_URL (CVSS 5.3)
  local required_rce="1.0.111"   # CVE-2025-59536 hooks RCE (CVSS 8.7)
  local fail=0
  if ! printf '%s\n%s\n' "$required_exfil" "$ver" | sort -V -C 2>/dev/null; then
    echo "  ! CC $ver < $required_exfil — CVE-2026-21852 unfixed (API key exfil). Run: npm i -g @anthropic-ai/claude-code"
    fail=1
  fi
  if ! printf '%s\n%s\n' "$required_rce" "$ver" | sort -V -C 2>/dev/null; then
    echo "  ! CC $ver < $required_rce — CVE-2025-59536 unfixed (hooks RCE). Run: npm i -g @anthropic-ai/claude-code"
    fail=1
  fi
  [ "$fail" -eq 1 ] && exit 1
  echo "  + CC $ver — CVE-2026-21852 and CVE-2025-59536 OK"
}
check_cc_version
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
# Rules are loaded by the plugin (system/rules/). Bootstrap no longer copies them
# to ~/.claude/rules/ to avoid double-loading and divergence. (t-760, 2026-03-30)
echo "Rules: loaded by plugin (skipping bootstrap copy)"
if [ -d "$TARGET_DIR/rules" ] && ! $CHECK_ONLY; then
    rule_count=$(ls "$TARGET_DIR/rules"/*.md 2>/dev/null | wc -l)
    if [ "$rule_count" -gt 0 ]; then
        echo "  Cleaning stale bootstrap rules ($rule_count files)..."
        rm -f "$TARGET_DIR/rules"/*.md
        rmdir "$TARGET_DIR/rules" 2>/dev/null || true
    fi
fi

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

# --- Step 4b: Remove PostToolUse hooks from settings.json (cleanup) ---
# CC reads hooks.json once at session startup — hooks must be present before the session starts.
# These hooks now live in system/hooks/hooks.json. Remove the old workaround entries.
echo "PostToolUse hooks (cleanup):"
SETTINGS_FILE="$TARGET_DIR/settings.json"
if [ -f "$SETTINGS_FILE" ] && command -v jq &>/dev/null; then
    CURRENT_HOOKS=$(jq '.hooks // {}' "$SETTINGS_FILE" 2>/dev/null)
    if [ "$CURRENT_HOOKS" = "{}" ]; then
        echo "  = settings.json .hooks already empty"
    else
        CHANGES=$((CHANGES + 1))
        if $CHECK_ONLY; then
            echo "  ~ settings.json .hooks (would remove — now served by plugin hooks.json)"
        else
            jq 'del(.hooks)' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
                && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
            echo "  ~ settings.json .hooks removed (now served by plugin hooks.json)"
        fi
    fi
elif [ ! -f "$SETTINGS_FILE" ]; then
    echo "  = settings.json not found (nothing to clean)"
else
    echo "  ! jq not found (cannot remove .hooks from settings.json)"
fi

# --- Step 4c: CC undercover mode (no attribution in commits/PRs) ---
# Per system/rules/git-discipline.md "Commit attribution — HARD RULE".
# Sets CC-native attribution.commit/.pr to empty strings so the agent loop
# never proposes adding Co-Authored-By or similar trailers.
echo "Undercover mode (settings.json attribution):"
if [ -f "$SETTINGS_FILE" ] && command -v jq &>/dev/null; then
    CURRENT_ATTR=$(jq '.attribution // {}' "$SETTINGS_FILE" 2>/dev/null)
    DESIRED_ATTR='{"commit":"","pr":""}'
    if [ "$CURRENT_ATTR" = "$DESIRED_ATTR" ] 2>/dev/null; then
        echo "  = settings.json attribution (already empty — undercover on)"
    else
        CHANGES=$((CHANGES + 1))
        if $CHECK_ONLY; then
            echo "  ~ settings.json attribution (would set commit='' and pr='')"
        else
            jq '.attribution = {"commit":"","pr":""}' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
                && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
            echo "  ~ settings.json attribution (set commit='' and pr='' — undercover on)"
        fi
    fi
else
    echo "  ! settings.json or jq not available (skipping undercover mode)"
fi

# --- Step 4d: Git pre-commit hook (no-attribution backstop) ---
# Deploys the pre-commit hook template to ~/.config/git/hooks/. Does NOT
# automatically set core.hooksPath globally — that's an opt-in (printed below).
# Past sessions have repeatedly violated the no-attribution rule despite the
# soft mechanisms; this is the git-side hard backstop.
echo "Git pre-commit hook (no-attribution backstop):"
GIT_HOOK_SRC="$SYSTEM_DIR/scripts/git-hooks/pre-commit"
GIT_HOOK_DIR="$HOME/.config/git/hooks"
GIT_HOOK_DST="$GIT_HOOK_DIR/pre-commit"
GIT_HOOK_COMMITMSG_DST="$GIT_HOOK_DIR/commit-msg"
if [ -f "$GIT_HOOK_SRC" ]; then
    if ! $CHECK_ONLY; then
        mkdir -p "$GIT_HOOK_DIR"
    fi
    sync_file "$GIT_HOOK_SRC" "$GIT_HOOK_DST" "git/hooks/pre-commit"
    sync_file "$GIT_HOOK_SRC" "$GIT_HOOK_COMMITMSG_DST" "git/hooks/commit-msg"
    if ! $CHECK_ONLY; then
        chmod +x "$GIT_HOOK_DST" "$GIT_HOOK_COMMITMSG_DST" 2>/dev/null || true
    fi

    # Check if core.hooksPath is set; if not, print activation hint
    CURRENT_HOOKS_PATH=$(git config --global --get core.hooksPath 2>/dev/null || echo "")
    if [ -z "$CURRENT_HOOKS_PATH" ]; then
        echo "  ! To activate globally, run: git config --global core.hooksPath ~/.config/git/hooks"
        echo "    (this is opt-in — bootstrap does NOT set it automatically)"
    elif [ "$CURRENT_HOOKS_PATH" = "$GIT_HOOK_DIR" ]; then
        echo "  = core.hooksPath already set to $GIT_HOOK_DIR (active)"
    else
        echo "  ! core.hooksPath is set to: $CURRENT_HOOKS_PATH (not our path — hooks NOT active)"
        echo "    To switch, run: git config --global core.hooksPath ~/.config/git/hooks"
    fi
else
    echo "  — git-hooks/pre-commit template not found in source"
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

# --- Step 6: ruflo runtime ---
echo "ruflo:"
CF_BIN=""
for name in ruflo claude-flow; do
    for candidate in "$HOME"/.nvm/versions/node/*/bin/$name; do
        [ -x "$candidate" ] && CF_BIN="$candidate" && break 2
    done
done

if [ -n "$CF_BIN" ]; then
    CF_BIN_NAME="$(basename "$CF_BIN")"
    CF_PKG_DIR="$(dirname "$CF_BIN")/../lib/node_modules/$CF_BIN_NAME"

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
    echo "  — ruflo not found (Layer 0 fallback)"
fi

# --- Step 6b: MCP servers in settings.local.json ---
# Personal infrastructure MCP servers (ruflo) go in settings.local.json
# (gitignored, per-machine). Project-specific MCP (brana) stays in .mcp.json.
echo "MCP servers (settings.local.json):"
SETTINGS_LOCAL="$TARGET_DIR/settings.local.json"

# Build MCP servers object based on what's installed
MCP_SERVERS="{}"

# ruflo (required — core memory backbone)
RUFLO_WRAPPER="$SYSTEM_DIR/scripts/ruflo-mcp.sh"
if [ -x "$RUFLO_WRAPPER" ] || [ -f "$RUFLO_WRAPPER" ]; then
    MCP_SERVERS=$(echo "$MCP_SERVERS" | jq --arg cmd "$RUFLO_WRAPPER" \
        '.ruflo = {"command": $cmd, "args": ["mcp", "start"], "env": {"CLAUDE_FLOW_TOOL_GROUPS": "memory,agentdb,embeddings,hooks"}}')
    echo "  + ruflo → $RUFLO_WRAPPER"
elif [ -n "$CF_BIN" ]; then
    MCP_SERVERS=$(echo "$MCP_SERVERS" | jq --arg cmd "$CF_BIN" \
        '.ruflo = {"command": $cmd, "args": ["mcp", "start"], "env": {"CLAUDE_FLOW_TOOL_GROUPS": "memory,agentdb,embeddings,hooks"}}')
    echo "  + ruflo → $CF_BIN (direct, no PID lock)"
else
    echo "  — ruflo (not found, skip)"
fi

# Write settings.local.json if we have any servers
if [ "$MCP_SERVERS" != "{}" ] && command -v jq &>/dev/null; then
    if [ -f "$SETTINGS_LOCAL" ]; then
        CURRENT_MCP=$(jq '.mcpServers // {}' "$SETTINGS_LOCAL" 2>/dev/null) || CURRENT_MCP="{}"
    else
        CURRENT_MCP="{}"
    fi

    if [ "$CURRENT_MCP" = "$MCP_SERVERS" ] 2>/dev/null; then
        echo "  = settings.local.json mcpServers (unchanged)"
    else
        CHANGES=$((CHANGES + 1))
        if $CHECK_ONLY; then
            echo "  ~ settings.local.json mcpServers (would update)"
        else
            if [ -f "$SETTINGS_LOCAL" ]; then
                jq --argjson mcp "$MCP_SERVERS" '.mcpServers = $mcp' "$SETTINGS_LOCAL" > "$SETTINGS_LOCAL.tmp" \
                    && mv "$SETTINGS_LOCAL.tmp" "$SETTINGS_LOCAL"
            else
                jq -n --argjson mcp "$MCP_SERVERS" '{mcpServers: $mcp}' > "$SETTINGS_LOCAL"
            fi
            echo "  ~ settings.local.json mcpServers (updated)"
        fi
    fi
else
    echo "  — no MCP servers to configure"
fi

# --- Step 7: Plugin auto-registration ---
echo "Plugin registration:"
PLUGINS_DIR="$TARGET_DIR/plugins"
mkdir -p "$PLUGINS_DIR/cache" "$PLUGINS_DIR/marketplaces"

# 7a: Register brana marketplace in known_marketplaces.json
KNOWN_MP="$PLUGINS_DIR/known_marketplaces.json"
if [ ! -f "$KNOWN_MP" ]; then
    if ! $CHECK_ONLY; then
        echo '{}' > "$KNOWN_MP"
    fi
fi
if command -v jq &>/dev/null; then
    BRANA_MP=$(jq -r '.brana // empty' "$KNOWN_MP" 2>/dev/null)
    if [ -z "$BRANA_MP" ]; then
        CHANGES=$((CHANGES + 1))
        if $CHECK_ONLY; then
            echo "  + known_marketplaces.json (would add brana)"
        else
            NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
            jq --arg loc "$PLUGINS_DIR/marketplaces/brana" \
               --arg now "$NOW" \
               '. + {"brana": {"source": {"source": "github", "repo": "martineserios/thebrana"}, "installLocation": $loc, "lastUpdated": $now, "autoUpdate": true}}' \
               "$KNOWN_MP" > "$KNOWN_MP.tmp" && mv "$KNOWN_MP.tmp" "$KNOWN_MP"
            echo "  + known_marketplaces.json (brana marketplace registered)"
        fi
    else
        echo "  = known_marketplaces.json (brana already registered)"
    fi
fi

# 7b: Symlink marketplace source (local repo → marketplace dir)
MP_LINK="$PLUGINS_DIR/marketplaces/brana"
if [ -L "$MP_LINK" ]; then
    CURRENT_TARGET=$(readlink -f "$MP_LINK" 2>/dev/null || true)
    if [ "$CURRENT_TARGET" = "$(readlink -f "$SCRIPT_DIR")" ]; then
        echo "  = marketplaces/brana (symlink current)"
    else
        CHANGES=$((CHANGES + 1))
        if ! $CHECK_ONLY; then
            rm "$MP_LINK"
            ln -s "$SCRIPT_DIR" "$MP_LINK"
            echo "  ~ marketplaces/brana (symlink updated)"
        else
            echo "  ~ marketplaces/brana (would update symlink)"
        fi
    fi
elif [ -d "$MP_LINK" ]; then
    # Real directory exists (from git clone) — replace with symlink for dev
    CHANGES=$((CHANGES + 1))
    if ! $CHECK_ONLY; then
        rm -rf "$MP_LINK"
        ln -s "$SCRIPT_DIR" "$MP_LINK"
        echo "  ~ marketplaces/brana (replaced clone with symlink to local repo)"
    else
        echo "  ~ marketplaces/brana (would replace clone with symlink)"
    fi
else
    CHANGES=$((CHANGES + 1))
    if ! $CHECK_ONLY; then
        ln -s "$SCRIPT_DIR" "$MP_LINK"
        echo "  + marketplaces/brana (symlinked to local repo)"
    else
        echo "  + marketplaces/brana (would symlink to local repo)"
    fi
fi

# 7c: Snapshot system/ to plugin cache
PLUGIN_VERSION=$(jq -r '.version // "0.0.0"' "$SYSTEM_DIR/.claude-plugin/plugin.json" 2>/dev/null || echo "0.0.0")
CACHE_DIR="$PLUGINS_DIR/cache/brana/brana/$PLUGIN_VERSION"
if [ -d "$CACHE_DIR" ]; then
    # Check if cache is stale (compare with system/)
    CACHE_DIFF=$(diff -rq "$CACHE_DIR" "$SYSTEM_DIR" 2>/dev/null | grep -v ".claude-plugin" | head -5 || true)
    if [ -n "$CACHE_DIFF" ]; then
        CHANGES=$((CHANGES + 1))
        if $CHECK_ONLY; then
            echo "  ~ cache/brana/brana/$PLUGIN_VERSION (would sync)"
        else
            rsync -av --delete --exclude='.claude-plugin' "$SYSTEM_DIR/" "$CACHE_DIR/" > /dev/null
            mkdir -p "$CACHE_DIR/.claude-plugin"
            cp "$SYSTEM_DIR/.claude-plugin/plugin.json" "$CACHE_DIR/.claude-plugin/plugin.json"
            echo "  ~ cache/brana/brana/$PLUGIN_VERSION (synced)"
        fi
    else
        echo "  = cache/brana/brana/$PLUGIN_VERSION (current)"
    fi
else
    CHANGES=$((CHANGES + 1))
    if $CHECK_ONLY; then
        echo "  + cache/brana/brana/$PLUGIN_VERSION (would snapshot)"
    else
        mkdir -p "$CACHE_DIR/.claude-plugin"
        rsync -av --exclude='.git' "$SYSTEM_DIR/" "$CACHE_DIR/" > /dev/null
        cp "$SYSTEM_DIR/.claude-plugin/plugin.json" "$CACHE_DIR/.claude-plugin/plugin.json"
        echo "  + cache/brana/brana/$PLUGIN_VERSION (snapshotted)"
    fi
fi

# 7d: Register in installed_plugins.json
# CC uses "name@marketplace" keys with array values: [{scope, installPath, version, ...}]
INSTALLED="$PLUGINS_DIR/installed_plugins.json"
PLUGIN_KEY="brana@brana"
if [ ! -f "$INSTALLED" ]; then
    if ! $CHECK_ONLY; then
        echo '{"version": 2, "plugins": {}}' > "$INSTALLED"
    fi
fi
if command -v jq &>/dev/null; then
    # Get current git SHA for tracking
    GIT_SHA=$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")

    BRANA_INSTALLED=$(jq -r --arg key "$PLUGIN_KEY" '.plugins[$key] // empty' "$INSTALLED" 2>/dev/null)
    if [ -z "$BRANA_INSTALLED" ] || [ "$BRANA_INSTALLED" = "null" ]; then
        CHANGES=$((CHANGES + 1))
        if $CHECK_ONLY; then
            echo "  + installed_plugins.json (would register $PLUGIN_KEY)"
        else
            NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
            jq --arg key "$PLUGIN_KEY" \
               --arg ver "$PLUGIN_VERSION" \
               --arg path "$CACHE_DIR" \
               --arg now "$NOW" \
               --arg sha "$GIT_SHA" \
               '.plugins[$key] = [{"scope": "user", "installPath": $path, "version": $ver, "installedAt": $now, "lastUpdated": $now, "gitCommitSha": $sha}]' \
               "$INSTALLED" > "$INSTALLED.tmp" && mv "$INSTALLED.tmp" "$INSTALLED"
            echo "  + installed_plugins.json ($PLUGIN_KEY registered)"
        fi
    else
        # Update version/path/sha if changed
        INSTALLED_VER=$(jq -r --arg key "$PLUGIN_KEY" '.plugins[$key][0].version // ""' "$INSTALLED" 2>/dev/null)
        INSTALLED_SHA=$(jq -r --arg key "$PLUGIN_KEY" '.plugins[$key][0].gitCommitSha // ""' "$INSTALLED" 2>/dev/null)
        if [ "$INSTALLED_VER" != "$PLUGIN_VERSION" ] || [ "$INSTALLED_SHA" != "$GIT_SHA" ]; then
            CHANGES=$((CHANGES + 1))
            if $CHECK_ONLY; then
                echo "  ~ installed_plugins.json (would update $PLUGIN_KEY v$INSTALLED_VER → v$PLUGIN_VERSION)"
            else
                NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
                jq --arg key "$PLUGIN_KEY" \
                   --arg ver "$PLUGIN_VERSION" \
                   --arg path "$CACHE_DIR" \
                   --arg now "$NOW" \
                   --arg sha "$GIT_SHA" \
                   '.plugins[$key] = [{"scope": "user", "installPath": $path, "version": $ver, "installedAt": (.plugins[$key][0].installedAt // $now), "lastUpdated": $now, "gitCommitSha": $sha}]' \
                   "$INSTALLED" > "$INSTALLED.tmp" && mv "$INSTALLED.tmp" "$INSTALLED"
                echo "  ~ installed_plugins.json ($PLUGIN_KEY updated → v$PLUGIN_VERSION @ ${GIT_SHA:0:7})"
            fi
        else
            echo "  = installed_plugins.json ($PLUGIN_KEY v$PLUGIN_VERSION registered)"
        fi
    fi
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
    echo "Plugin (skills, agents, hooks):"
    echo "  - Registered in installed_plugins.json"
    echo "  - Cache at: $PLUGINS_DIR/cache/brana/brana/$PLUGIN_VERSION"
    echo "  - Dev override: claude --plugin-dir ./system"
    echo ""
    # Invalidate skills mtime marker so next session does a full reindex
    rm -f /tmp/brana-skills-index-mtime 2>/dev/null || true
    # Signal session-start hook to surface the restart reminder as a banner
    touch /tmp/brana-bootstrap-pending-restart 2>/dev/null || true
    echo "Start a new Claude Code session to activate."
    echo "  ! Hook config may have changed — restart CC for hooks to take effect."
    echo ""
    echo "Workspace layout: docs/guide/ecosystem.md"
fi
