---
status: accepted
---
# ADR-036: MCP-or-CLI Decision Rule

**Date:** 2026-04-10
**Status:** Accepted
**Deciders:** Martin Rios

## Context

Vasilev's "I deleted everything" argument (Cluster D, URL batch research 2026-04-08):
most MCPs are help-surface layers for tools that already have CLIs. A GitHub MCP
measured at ~54K tokens vs `gh --help` at ~562. Help-surface MCPs consume context
budget the agent needs for reasoning, and every server in `.mcp.json` adds blocking
startup latency (CC blocks on all MCP servers at init — `anthropics/claude-code#26666`,
not planned to fix).

Brana currently runs 2 project-level MCPs (`brana-mcp`, `ruflo`) and 1 global MCP
(`google-sheets`). The global server still uses `uvx` — a direct violation of ADR-033.

## Decision Rule

```
IF the interaction is stateless (help, command, lookup, one-shot API call):
  → Use CLI.
  Reasons: no blocking startup cost, no context overhead, version-controlled,
           debuggable, --help self-documenting, composable in shell pipelines.

IF the interaction is stateful (live index, persistent connection, structured JSON API,
                                session or memory store):
  → Use MCP.
  Reasons: structured JSON reduces tokens vs plain text, persistent connection
           amortizes startup cost, native tool-call integration.
```

## Audit of Current Stack

| Server | Location | Classification | Decision | Rationale |
|--------|----------|---------------|----------|-----------|
| `brana` | `.mcp.json` (project) | Stateful — owns backlog + session JSON API | **KEEP** | Structured JSON saves 65% tokens vs CLI output. Battle-tested. |
| `ruflo` | `.mcp.json` (project) | Stateful — AgentDB, HNSW vector index, connection-based | **KEEP** | No viable CLI equivalent for semantic search + memory store. |
| `google-sheets` | `~/.claude.json` (global) | Stateless — one-shot Sheets API calls via service account | **FIX + AUDIT** | Violates ADR-033 (`uvx` at startup). Pin to pre-installed binary first. Evaluate CLI migration separately (t-1110 follow-up). |
| `linkedin-mcp` | (not currently configured) | Stateless — patchright browser scraper | **DO NOT RE-ADD** | Brittle, rate-limited (24h blocks), high maintenance. Use `brana feed` or manual lookup. |
| `context7` | (not currently configured) | Stateless — library docs lookup | **DO NOT RE-ADD** | Help-surface layer. Use web search or vendor docs directly. |

## Immediate Actions

1. **Fix `google-sheets` ADR-033 violation** — replace `uvx` command with pre-installed
   binary path in `~/.claude.json`. Schedule weekly update alongside existing reindex job.
2. **Do not re-add `linkedin-mcp` or `context7`** — they are absent from current configs;
   keep them absent.

## Non-Actions

- No migration of `google-sheets` to a CLI today. The ADR-033 fix (pin the binary) is the
  minimum viable action. Full CLI migration is a separate effort if the need arises.
- No new MCP servers without passing this decision rule first.

## Consequences

- Every new integration now has a clear classification test before deciding MCP vs CLI.
- Cold-start blocking risk is bounded: only stateful servers that justify their cost
  belong in `.mcp.json`.
- `google-sheets` ADR-033 violation is called out and owned (tracked via this ADR).
- `linkedin-mcp` and `context7` are explicitly retired — no ambiguity about whether to
  restore them.

## References

- [ADR-033: Pin MCP Servers to Pre-installed Binaries](./ADR-033-pin-mcp-servers.md)
- [docs/research/2026-04-08-url-batch-findings.md §Cluster D](../research/2026-04-08-url-batch-findings.md)
- Source task: t-1110

## Field Notes

**2026-04-10 — ADR Non-Actions are session constraints, not suggestions.**
In the same session this ADR was written, the user asked to do the exact thing the
Non-Actions section prohibited (build a `brana gsheets` CLI). Running `/brana:challenge`
caught the contradiction. The challenger's highest-value use case: protecting freshly-written
decisions from the author's own recency bias. Pattern: "author recency bias" — the decision
writer is also the most likely person to immediately override it.
