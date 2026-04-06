#!/bin/bash
# Wrapper: start linkedin-scraper MCP server from uv tool install.
# Resolves from ~/.local/bin or PATH — no hardcoded paths.

BIN="$HOME/.local/bin/linkedin-scraper-mcp"
[ ! -x "$BIN" ] && BIN="$(command -v linkedin-scraper-mcp 2>/dev/null)"
[ ! -x "${BIN:-}" ] && { echo "linkedin-scraper-mcp not found. Install: uv tool install linkedin-scraper-mcp" >&2; exit 1; }

exec "$BIN" "$@"
