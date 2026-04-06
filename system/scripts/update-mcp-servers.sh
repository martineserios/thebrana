#!/bin/bash
# Weekly MCP server update — keeps pinned binaries fresh.
# Scheduled: Sunday 3am via brana-scheduler.
# Manual: bash system/scripts/update-mcp-servers.sh
set -euo pipefail

LOG="$HOME/.claude/mcp-update.log"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log() { echo "[$TIMESTAMP] $1" | tee -a "$LOG"; }

# Source nvm
if [ -f "$HOME/.nvm/nvm.sh" ]; then
    export NVM_DIR="$HOME/.nvm"
    . "$NVM_DIR/nvm.sh" --no-use 2>/dev/null
    NODE_BIN="$(nvm which default 2>/dev/null | sed 's|/node$||')"
    NPM="${NODE_BIN}/npm"
else
    NPM="$(command -v npm 2>/dev/null)"
fi

if [ -z "${NPM:-}" ] || [ ! -x "$NPM" ]; then
    log "ERROR: npm not found"
    exit 1
fi

log "Starting MCP server update"

# Update ruflo
if "$NPM" i -g ruflo@latest 2>&1 | tail -1; then
    log "OK: ruflo updated"
else
    log "WARN: ruflo update failed"
fi

# Update context7
if "$NPM" i -g @upstash/context7-mcp@latest 2>&1 | tail -1; then
    log "OK: context7-mcp updated"
else
    log "WARN: context7-mcp update failed"
fi

# Update linkedin-scraper-mcp
if command -v uv >/dev/null 2>&1; then
    if uv tool upgrade linkedin-scraper-mcp 2>&1 | tail -1; then
        log "OK: linkedin-scraper-mcp updated"
    else
        log "WARN: linkedin-scraper-mcp update failed"
    fi
else
    log "SKIP: uv not found, linkedin-scraper-mcp not updated"
fi

log "MCP server update complete"

# Health check: warn if last update is >14 days old
if [ -f "$LOG" ]; then
    LAST_OK=$(grep "update complete" "$LOG" | tail -1 | grep -oP '\d{4}-\d{2}-\d{2}' | head -1)
    if [ -n "$LAST_OK" ]; then
        DAYS_AGO=$(( ($(date +%s) - $(date -d "$LAST_OK" +%s 2>/dev/null || echo 0)) / 86400 )) 2>/dev/null || DAYS_AGO=0
        if [ "$DAYS_AGO" -gt 14 ]; then
            log "ALERT: Last successful update was $DAYS_AGO days ago"
        fi
    fi
fi
