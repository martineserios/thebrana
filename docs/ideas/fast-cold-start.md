# Fast Cold Start for Brana Plugin

> Brainstormed 2026-04-06. Status: idea.

## Problem

Brana plugin startup takes 4+ minutes (measured: 4m9s on proyecto_anita) due to npm/pip package resolution on every MCP server launch, plus a heavyweight session-start hook with 4 parallel network/Python jobs. CC blocks the interactive prompt until ALL MCP servers complete initialization — no lazy loading exists or is planned.

## Root cause analysis

### MCP server cold starts (80-90% of latency)

CC starts all MCP servers in parallel but **blocks until ALL complete the `initialize` handshake**. Current config uses package managers that resolve on every start:

| Server | Command | Cold start | Why slow |
|--------|---------|-----------|----------|
| ruflo | `npm exec ruflo@latest mcp start` | 60-180s | npm registry resolution every time |
| context7 | `npx @upstash/context7-mcp@latest` | 30-90s | npm registry resolution every time |
| linkedin | `uvx linkedin-scraper-mcp` | 15-30s | pip resolution + heavyweight imports |
| brana | native binary | <100ms | Already fast |

### Session-start hook (10-20% of latency)

600-line hook running 4 parallel jobs:
- ruflo CLI pattern search (2-4s) — **keep, merge into 1 call**
- ruflo CLI correction search (2-4s) — **merge into above**
- python3 spec-graph staleness (1-2s) — **kill or port to Rust**
- uv run decisions.py (2-4s) — **kill or port to Rust**

### Known CC bugs that may contribute

- **#35287 (OPEN):** stdio MCP server that fails init hangs CC indefinitely — no timeout fires
- **#40207 (OPEN):** CC sends SIGTERM to healthy MCP servers after 10-60s, causing reconnection loops
- **#43299 (CLOSED, not fixed):** `MCP_TIMEOUT` env var is broken — SDK hardcodes 60s, ignores the var
- **#26666 (CLOSED, not planned):** Lazy MCP loading requested, explicitly rejected

## Research findings

- CC starts MCP servers in parallel, blocks until all ready (confirmed via issue #29033 debug logs)
- No lazy loading planned — 3 separate requests closed as "not planned"
- `MCP_TIMEOUT` env var is non-functional (SDK hardcodes `requestTimeout: 60000ms`)
- `MCP_CONNECTION_NONBLOCKING=true` only works in `-p` (headless) mode
- ruflo itself initializes cleanly in <1s — the binary is fast, npx resolution is slow
- npx adds 2-8s overhead even when cached; direct binary invocation is "instant" per reports
- v2.1.89 added 5s bound for `--mcp-config` (headless only), interactive sessions still unbound

## Proposed solution

Three parallel tracks: pin (quick win), trim (reduce hook overhead), instrument (diagnose remaining issues).

### Track 1 — Pin MCP servers to pre-installed binaries

Replace package-manager invocations with direct binary paths in `.mcp.json`:

```json
{
  "mcpServers": {
    "ruflo": {
      "command": "/home/martineserios/.nvm/versions/node/v20.19.0/bin/ruflo",
      "args": ["mcp", "start"],
      "env": { "CLAUDE_FLOW_TOOL_GROUPS": "memory,agentdb,embeddings,hooks" }
    },
    "context7": {
      "command": "<path-to-globally-installed-context7-mcp>"
    },
    "linkedin": {
      "command": "<path-to-uv-tool-installed-linkedin-scraper-mcp>"
    },
    "brana": {
      "command": "<path-to-brana-mcp-binary>"
    }
  }
}
```

Steps:
1. Verify ruflo global install: `which ruflo` → should be nvm path
2. Install context7 globally: `npm i -g @upstash/context7-mcp`
3. Pin linkedin: `uv tool install linkedin-scraper-mcp`
4. Update `.mcp.json` with absolute paths
5. Add weekly auto-update scheduled job (Sunday 3am):
   ```bash
   npm i -g ruflo@latest @upstash/context7-mcp@latest
   uv tool upgrade linkedin-scraper-mcp
   ```

**Expected impact:** MCP startup drops from 60-240s to <2s per server.

### Track 2 — Trim session-start hook

1. Merge 2 ruflo CLI calls into 1 broader query
2. Kill Python spec-graph staleness check (port to `brana graph stats --stale` if needed later)
3. Kill Python decisions.py job (port to `brana ops decisions --severity HIGH` if needed later)
4. Reduce parallel wait budget from 5s to 2s

**Expected impact:** Hook execution drops from 5-10s to 1-3s.

### Track 3 — Add startup diagnostic instrumentation

Create a lightweight MCP server wrapper script that logs timing:

```bash
#!/usr/bin/env bash
# mcp-wrapper.sh — wraps any MCP server with startup timing
SERVER_NAME="$1"; shift
START=$(date +%s%3N)
echo "[brana-diag] $SERVER_NAME starting at $START" >> /tmp/brana-mcp-timing.log
exec "$@"
# Note: post-init timing would need a side-channel since exec replaces the process
```

Use in `.mcp.json`:
```json
"ruflo": {
  "command": "/path/to/mcp-wrapper.sh",
  "args": ["ruflo", "/path/to/ruflo", "mcp", "start"]
}
```

Also instrument session-start.sh with timing marks:
```bash
echo "[brana-diag] hook-start $(date +%s%3N)" >> /tmp/brana-startup-timing.log
# ... each phase ...
echo "[brana-diag] hook-end $(date +%s%3N)" >> /tmp/brana-startup-timing.log
```

After 3-5 sessions, review `/tmp/brana-*-timing.log` to confirm where time goes and whether pinning was sufficient.

## Risks

| Risk | Mitigation |
|------|-----------|
| Pinned binary path changes after npm update | Use `which ruflo` in wrapper, or symlink |
| Weekly update job fails silently | Add health check: log last-update timestamp, alert if >14 days stale |
| Remaining hang from #35287 | Diagnostic wrapper will reveal it; manual workaround: remove offending server from .mcp.json |
| SIGTERM bug (#40207) kills servers mid-session | Unrelated to startup; `/mcp` reconnects; no fix available |
| Merged ruflo query returns noisier results | Use broader query with `limit: 10`, filter client-side |

## Expected results

| Metric | Before | After (projected) |
|--------|--------|-------------------|
| MCP cold start | 60-240s | <2s |
| Session-start hook | 5-10s | 1-3s |
| Skill registration | 2-5s | 2-5s (unchanged) |
| **Total cold start** | **4+ minutes** | **~5-10 seconds** |

## Next steps

1. Implement Track 1 (pin MCP servers) — 30 min
2. Implement Track 3 (diagnostics) — 30 min
3. Measure 3-5 sessions
4. Implement Track 2 (trim hook) based on diagnostic data
5. Add weekly auto-update scheduled job

## References

- anthropics/claude-code#35287 — MCP stdio hang bug
- anthropics/claude-code#40207 — SIGTERM kills healthy servers
- anthropics/claude-code#43299 — MCP_TIMEOUT broken
- anthropics/claude-code#26666 — Lazy loading not planned
- anthropics/claude-code#7575 — 60s hard timeout cap
