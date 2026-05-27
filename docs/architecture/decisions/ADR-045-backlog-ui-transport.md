# ADR-045 — Backlog web UI transport: CLI shell-out vs axum sidecar

**Status:** Accepted  
**Date:** 2026-05-27  
**Blocked-by:** t-1509 (spike: transport layer options for brana backlog web UI)

## Context

The brana backlog web UI (idea doc: `docs/ideas/brana-backlog-web-ui.md`) needs a transport
layer between the Next.js frontend and `tasks.json`. Three options were evaluated:

| Option | Description |
|--------|-------------|
| **A — CLI shell-out** | Next.js API routes call `brana` CLI via `execFile` |
| **B — brana-mcp** | Next.js talks to the existing MCP server |
| **C — axum sidecar** | New HTTP server in `brana-mcp` crate exposes REST endpoints |

t-1509 spike measured Option A latency on a realistic board-load sequence:
- P50: 17ms per call
- P95: ~40ms per call
- 5-call board load: 89ms total
- t-1502 milestone threshold: 300ms

## Decision

Use **CLI shell-out** (Option A). Next.js API routes invoke the `brana` binary via
`execFile` with an argv array (no shell interpolation).

**Read surface:**
```
execFile('brana', ['backlog', 'query', '--json', '--status', status])
execFile('brana', ['backlog', 'get', taskId, '--json'])
```

**Write surface:**
```
execFile('brana', ['backlog', 'set', taskId, field, value])
execFile('brana', ['backlog', 'add', '--json', payload])
```

**Injection mitigation:** `execFile` with an explicit `args[]` array (not `exec` with a
shell string) prevents shell injection. Task IDs and field values are passed as discrete
argv elements, never interpolated into a command string.

**V1 scope:** Local-only. The Next.js dev server and `brana` binary share the same machine.
No auth layer in V1.

## Rejected alternatives

### Option B — brana-mcp

`brana-mcp` uses stdio transport (stdin/stdout JSON-RPC). It is not an HTTP server —
there is no port to connect to from a browser or Next.js API route. Adapting it to HTTP
would require adding an HTTP transport layer, which is essentially Option C.

Additionally, MCP tools are scoped to CC sessions (per `feedback_mcp-allowed-tools-project-scoped.md`).
A Next.js app running outside CC cannot call brana-mcp directly.

### Option C — axum sidecar

Adding an HTTP server to `brana-mcp` would solve the connectivity problem but introduces
1–2 weeks of Rust infrastructure work: HTTP routing, serialization, lifecycle management
(startup/shutdown, port conflict handling), and a new process dependency for the web UI.

The spike showed no latency problem to solve — Option A is already under the 300ms
threshold by 7×. The infrastructure cost is not justified.

## Consequences

- No new Rust crates or HTTP servers required for V1.
- `brana` binary must be on `PATH` in the Next.js process environment (true on the local machine).
- Each API route call spawns a subprocess: acceptable at human UI interaction pace
  (drag-and-drop, button clicks), not suitable for high-frequency polling.
- If latency becomes a concern at scale (e.g., bulk operations), Option C can be adopted
  incrementally — the API route interface is the isolation boundary.

## Non-Actions

- **No axum sidecar in V1.** Revisit only if CLI shell-out latency exceeds 300ms under real load.
- **No WebSockets in V1.** Polling or on-demand fetch is sufficient for a local tool.
- **No auth layer in V1.** Local-only deployment; auth is a V2 concern if the UI is hosted.
