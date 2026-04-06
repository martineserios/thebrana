#!/bin/bash
# Wrapper: ensures ruflo MCP server reads ~/.swarm/memory.db
# instead of .swarm/ relative to whatever CWD CC launches from.
# Resolves ruflo from nvm or PATH — no hardcoded paths.
# Each CC session needs its own ruflo process (MCP stdio = one process per session).
# AgentDB v3 bridge uses better-sqlite3 with WAL mode for safe concurrent access.
# PID file is advisory (diagnostics only) — not a mutex.
cd "$HOME"

# --- PID file: advisory, not blocking ---
LOCKFILE="$HOME/.swarm/ruflo-mcp.pid"
mkdir -p "$HOME/.swarm"

if [ -f "$LOCKFILE" ]; then
    OLD_PID=$(cat "$LOCKFILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "ruflo MCP: another instance (pid $OLD_PID) running — starting new session instance" >&2
    fi
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
trap 'rm -f "$LOCKFILE"' EXIT

# Auto-restart on SIGTERM (CC SIGTERM bug #40207 kills healthy MCP servers).
# Run ruflo in foreground (no exec) so the wrapper survives SIGTERM and can restart.
# Max 5 restarts to avoid infinite loops on genuine failures.
MAX_RESTARTS=5
RESTART_COUNT=0
SIGTERM_RECEIVED=false

trap 'SIGTERM_RECEIVED=true' TERM

while true; do
    "$RUFLO" "$@" &
    RUFLO_PID=$!
    # Update lockfile with child PID so other instances detect it
    echo "$RUFLO_PID" > "$LOCKFILE"
    wait $RUFLO_PID 2>/dev/null
    EXIT_CODE=$?

    if [ "$SIGTERM_RECEIVED" = true ]; then
        SIGTERM_RECEIVED=false
        RESTART_COUNT=$((RESTART_COUNT + 1))
        if [ "$RESTART_COUNT" -ge "$MAX_RESTARTS" ]; then
            echo "ruflo MCP: max restarts ($MAX_RESTARTS) reached after SIGTERM, exiting" >&2
            break
        fi
        echo "ruflo MCP: SIGTERM received (CC bug #40207), restarting ($RESTART_COUNT/$MAX_RESTARTS)..." >&2
        sleep 1
        continue
    fi

    # Normal exit or non-SIGTERM signal — don't restart
    break
done
