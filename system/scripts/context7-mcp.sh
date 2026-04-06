#!/bin/bash
# Wrapper: start context7 MCP server from globally installed binary.
# Resolves from nvm or PATH — no hardcoded paths.

if [ -f "$HOME/.nvm/nvm.sh" ]; then
    export NVM_DIR="$HOME/.nvm"
    . "$NVM_DIR/nvm.sh" --no-use 2>/dev/null
    BIN="$(nvm which default 2>/dev/null | sed 's|/node$||')/context7-mcp"
fi
[ ! -x "${BIN:-}" ] && BIN="$(command -v context7-mcp 2>/dev/null)"
[ ! -x "${BIN:-}" ] && { echo "context7-mcp not found. Install: npm i -g @upstash/context7-mcp" >&2; exit 1; }

exec "$BIN" "$@"
