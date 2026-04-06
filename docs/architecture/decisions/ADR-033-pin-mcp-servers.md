# ADR-033: Pin MCP Servers to Pre-installed Binaries

**Date:** 2026-04-06
**Status:** accepted

## Context

Claude Code blocks the interactive prompt until ALL configured MCP servers complete the `initialize` handshake. This is sequential and synchronous -- no lazy loading exists or is planned (`anthropics/claude-code#26666`, closed as "not planned").

Three upstream issues compound the problem:

1. **No lazy loading** -- every server must init before the first prompt (`anthropics/claude-code#26666`)
2. **Broken timeout env var** -- `MCP_TIMEOUT` is ignored; the SDK hardcodes `requestTimeout: 60000ms` (`anthropics/claude-code#43299`)
3. **Hung init = hung session** -- a stdio server that fails init can hang CC indefinitely (`anthropics/claude-code#35287`)

Using `npx`, `npm exec`, or `uvx` in `.mcp.json` resolves packages from registries on every session start. This adds 15-180s per server depending on network conditions and cache state. Measured: **4m9s startup** on proyecto_anita with the plugin (4 MCP servers via npx/uvx).

Additionally, the SessionStart hook chain runs ruflo CLI calls and Python scripts (spec-graph, decisions.py) that add further latency before the first prompt is usable.

## Decision

**Always pin MCP servers to pre-installed binary paths in `.mcp.json`.** Never use `npx`, `npm exec`, or `uvx` as the command.

Pin pattern:

```json
{
  "mcpServers": {
    "example": {
      "command": "/home/user/.local/bin/example-mcp",
      "args": ["--stdio"]
    }
  }
}
```

Anti-pattern (banned):

```json
{
  "mcpServers": {
    "example": {
      "command": "npx",
      "args": ["-y", "example-mcp", "--stdio"]
    }
  }
}
```

A weekly scheduled job (Sunday 3am, alongside the existing knowledge reindex) updates pinned binaries via `npm install -g` / `uv tool install`. Urgent updates use manual `npm i -g <package>`.

**Also decided:** Trim the SessionStart hook chain:

- Merge 2 ruflo CLI calls into 1
- Kill Python `spec-graph.py` and `decisions.py` jobs (port to Rust CLI if needed later)

## Consequences

- MCP cold start drops from 60-240s to <2s per server (local binary, no registry resolution)
- Total session start time drops from ~4m to ~10s
- Weekly auto-update job keeps binaries fresh without manual intervention
- Manual `npm i -g` available for urgent updates between weekly runs
- ~3 days behind latest on average vs always-latest (acceptable trade-off)
- SessionStart hook becomes lighter: fewer subprocesses, no Python dependency at boot
- New MCP servers must be installed globally before adding to `.mcp.json` -- one extra setup step per server
