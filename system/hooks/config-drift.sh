#!/usr/bin/env bash
# Config drift detector — compares system/ source files vs deployed ~/.claude/ files.
# No strict mode — must always produce valid JSON.
#
# Usage:
#   Standalone:  bash config-drift.sh              (uses default paths)
#   From hook:   BRANA_SOURCE_DIR=... BRANA_DEPLOY_DIR=... bash config-drift.sh
#   From stdin:  echo '{"cwd":"/path"}' | bash config-drift.sh
#
# Output: JSON with status (clean|drifted) and array of drifted files.
# Each drifted entry: {file, type: modified|source_only|deploy_only}
#
# Environment overrides (for testing):
#   BRANA_SOURCE_DIR  — path to source directory (default: system/ in plugin root)
#   BRANA_DEPLOY_DIR  — path to deployed directory (default: ~/.claude/)

# Read stdin if available (hook mode), but don't block
INPUT=""
if [ ! -t 0 ]; then
    INPUT=$(cat 2>/dev/null) || true
fi

# Resolve source dir: env override > plugin root > git root
if [ -n "${BRANA_SOURCE_DIR:-}" ]; then
    SOURCE_DIR="$BRANA_SOURCE_DIR"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    SOURCE_DIR="$CLAUDE_PLUGIN_ROOT"
else
    CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || true
    if [ -n "$CWD" ]; then
        GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "$CWD")
        SOURCE_DIR="$GIT_ROOT/system"
    else
        GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
        SOURCE_DIR="$GIT_ROOT/system"
    fi
fi

# Resolve deploy dir: env override > ~/.claude/
DEPLOY_DIR="${BRANA_DEPLOY_DIR:-$HOME/.claude}"

# ── Collect files to compare ─────────────────────────────
# We compare: CLAUDE.md and rules/*.md
# These are the identity files that bootstrap.sh deploys.

DRIFTED_JSON="[]"

# Compare a single file. Args: relative_path [skip_source_only]
# skip_source_only: "true" suppresses source_only alerts (e.g. rules/ are plugin-served, not deployed by bootstrap.sh)
check_file() {
    local rel="$1"
    local skip_source_only="${2:-false}"
    local src="$SOURCE_DIR/$rel"
    local dst="$DEPLOY_DIR/$rel"

    if [ -f "$src" ] && [ -f "$dst" ]; then
        if ! diff -q "$src" "$dst" >/dev/null 2>&1; then
            DRIFTED_JSON=$(echo "$DRIFTED_JSON" | jq -c \
                --arg file "$rel" \
                '. + [{"file": $file, "type": "modified"}]')
        fi
    elif [ -f "$src" ] && [ ! -f "$dst" ]; then
        if [ "$skip_source_only" != "true" ]; then
            DRIFTED_JSON=$(echo "$DRIFTED_JSON" | jq -c \
                --arg file "$rel" \
                '. + [{"file": $file, "type": "source_only"}]')
        fi
    elif [ ! -f "$src" ] && [ -f "$dst" ]; then
        DRIFTED_JSON=$(echo "$DRIFTED_JSON" | jq -c \
            --arg file "$rel" \
            '. + [{"file": $file, "type": "deploy_only"}]')
    fi
}

# Check CLAUDE.md
check_file "CLAUDE.md"

# Check all rules from source
# rules/ are plugin-served — bootstrap.sh intentionally does NOT deploy them to ~/.claude/.
# Suppress source_only alerts (pass "true") to avoid false positives.
# deploy_only and modified alerts still fire (anomalies worth knowing).
if [ -d "$SOURCE_DIR/rules" ]; then
    for f in "$SOURCE_DIR/rules/"*.md; do
        [ -f "$f" ] || continue
        check_file "rules/$(basename "$f")" "true"
    done
fi

# Check deploy-only rules (exist in deploy but not source)
if [ -d "$DEPLOY_DIR/rules" ]; then
    for f in "$DEPLOY_DIR/rules/"*.md; do
        [ -f "$f" ] || continue
        local_name="rules/$(basename "$f")"
        if [ ! -f "$SOURCE_DIR/$local_name" ]; then
            check_file "$local_name"
        fi
    done
fi

# ── ADR-033: MCP pinning check on ~/.claude.json ─────────
# Walks both top-level mcpServers and project-scoped mcpServers.
# Flags any command containing npx or uvx.
MCP_VIOLATIONS_JSON="[]"
GLOBAL_JSON="$HOME/.claude.json"

if [ -f "$GLOBAL_JSON" ] && command -v jq &>/dev/null; then
    # Collect unique server names (top-level + project-scoped), deduplicated
    VIOLATIONS=$(jq -r '
      [
        (.mcpServers // {} | to_entries[] |
          select(.value.command // "" | test("npx|uvx")) |
          "top-level:\(.key)"),
        (.projects // {} | to_entries[] |
          (.value.mcpServers // {}) | to_entries[] |
          select(.value.command // "" | test("npx|uvx")) |
          "project-scoped:\(.key)")
      ] | unique[]
    ' "$GLOBAL_JSON" 2>/dev/null) || VIOLATIONS=""

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        MCP_VIOLATIONS_JSON=$(echo "$MCP_VIOLATIONS_JSON" | jq -c \
            --arg v "$line" '. + [$v]')
    done <<< "$VIOLATIONS"
fi

# ── Build output ─────────────────────────────────────────
COUNT=$(echo "$DRIFTED_JSON" | jq 'length' 2>/dev/null) || COUNT=0
MCP_COUNT=$(echo "$MCP_VIOLATIONS_JSON" | jq 'length' 2>/dev/null) || MCP_COUNT=0

if [ "$COUNT" -gt 0 ] || [ "$MCP_COUNT" -gt 0 ]; then
    STATUS="drifted"
else
    STATUS="clean"
fi

jq -n -c \
    --arg status "$STATUS" \
    --argjson drifted "$DRIFTED_JSON" \
    --argjson count "$COUNT" \
    --argjson mcp_violations "$MCP_VIOLATIONS_JSON" \
    --argjson mcp_count "$MCP_COUNT" \
    '{status: $status, count: $count, drifted: $drifted, mcp_violations: $mcp_violations, mcp_count: $mcp_count}'
