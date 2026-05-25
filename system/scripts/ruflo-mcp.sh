#!/bin/bash
# Wrapper: ensures ruflo MCP server reads ~/.swarm/memory.db
# instead of .swarm/ relative to whatever CWD CC launches from.
# Resolves ruflo from nvm or PATH — no hardcoded paths.
#
# IMPORTANT: must use `exec` to preserve stdin/stdout pipes for MCP stdio.
# Earlier versions backgrounded ruflo (`ruflo & wait`) to support SIGTERM/SIGHUP
# restart loops — that pattern silently broke JSON-RPC stdin delivery, so the
# MCP handshake never completed and ruflo showed as "failed" in /mcp.
# Restart on CC bug #40207 is handled by the user via /mcp reconnect.
# Use CLAUDE_PROJECT_DIR (CC-injected since v2.1.139) for project root so ruflo's
# own CWD heuristic resolves correctly; fall back to HOME for ~/.swarm/memory.db.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR:-}" ]; then
    cd "$CLAUDE_PROJECT_DIR"
else
    cd "$HOME"
fi

# Advisory PID file for diagnostics (not a mutex — AgentDB v3 uses WAL)
LOCKFILE="$HOME/.swarm/ruflo-mcp.pid"
mkdir -p "$HOME/.swarm"
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

# Resolution order:
#   1. nvm default node's bin/
#   2. any nvm-installed version that has ruflo (newest first)
#   3. PATH
if [ -f "$HOME/.nvm/nvm.sh" ]; then
    export NVM_DIR="$HOME/.nvm"
    . "$NVM_DIR/nvm.sh" --no-use 2>/dev/null
    RUFLO="$(nvm which default 2>/dev/null | sed 's|/node$||')/ruflo"
fi
if [ ! -x "${RUFLO:-}" ] && [ -d "$HOME/.nvm/versions/node" ]; then
    # Walk installed versions newest-first; stop at first hit
    NVM_DEFAULT_BIN="$(nvm which default 2>/dev/null | sed 's|/node$||')"
    while IFS= read -r node_bin; do
        candidate="${node_bin%/node}/ruflo"
        if [ -x "$candidate" ]; then
            RUFLO="$candidate"
            # Warn if this is not the nvm default — ruflo needs installing there
            actual_bin="${node_bin%/node}"
            if [ "$actual_bin" != "$NVM_DEFAULT_BIN" ]; then
                actual_ver="$(basename "$(dirname "$actual_bin")")"
                default_ver="$(basename "$(dirname "$NVM_DEFAULT_BIN")")"
                echo "[ruflo-mcp] WARN: ruflo found in nvm $actual_ver but nvm default is $default_ver — run: nvm use $actual_ver && npm install -g ruflo && nvm use default" >&2
            fi
            break
        fi
    done < <(find "$HOME/.nvm/versions/node" -name "node" -path "*/bin/node" | sort -rV)
fi
[ ! -x "${RUFLO:-}" ] && RUFLO="$(command -v ruflo 2>/dev/null)"
[ ! -x "${RUFLO:-}" ] && { echo "ruflo not found in nvm or PATH" >&2; exit 1; }

exec "$RUFLO" "$@"
