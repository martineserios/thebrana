#!/bin/bash
# Wrapper: ensures ruflo MCP server reads ~/.swarm/memory.db
# instead of .swarm/ relative to whatever CWD CC launches from.
# Resolves ruflo from nvm or PATH — no hardcoded paths.
# PID lock prevents concurrent instances corrupting SQLite (sql.js has no file locking).
cd "$HOME"

# --- PID lock: only one ruflo writer at a time ---
LOCKFILE="$HOME/.swarm/ruflo-mcp.pid"
mkdir -p "$HOME/.swarm"

if [ -f "$LOCKFILE" ]; then
    OLD_PID=$(cat "$LOCKFILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        # Another instance is alive — this session reuses it via MCP reconnect.
        # Exit cleanly so CC doesn't spawn a duplicate writer.
        echo "ruflo MCP already running (pid $OLD_PID), skipping duplicate" >&2
        exit 0
    fi
    # Stale lock — remove it
    rm -f "$LOCKFILE"
fi

# Try nvm default, then PATH
if [ -f "$HOME/.nvm/nvm.sh" ]; then
    export NVM_DIR="$HOME/.nvm"
    . "$NVM_DIR/nvm.sh" --no-use 2>/dev/null
    RUFLO="$(nvm which default 2>/dev/null | sed 's|/node$||')/ruflo"
fi
[ ! -x "${RUFLO:-}" ] && RUFLO="$(command -v ruflo 2>/dev/null)"
[ ! -x "${RUFLO:-}" ] && { echo "ruflo not found" >&2; exit 1; }

# Write PID lock and clean up on exit
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT INT TERM

exec "$RUFLO" "$@"
