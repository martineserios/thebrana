---
title: Brana Backlog Web UI
status: idea
created: 2026-05-19
---

# Brana Backlog Web UI

> Brainstormed 2026-05-19.

## Problem

The brana backlog lives in `tasks.json`, manipulated only via terminal CLI (`brana backlog`
commands). There is no visual layer for daily orientation, status-at-a-glance, or
cross-stream navigation. Daily backlog review is friction-heavy — you need to know the
right command to see the right slice of work.

## Proposed Solution

A web UI that renders the brana backlog using `brana-mcp` as the API. Hybrid layout:
Kanban board (status swim lanes) + CLI-feel list view (sortable, filterable). All writes
go through brana-mcp. CC stays in the terminal.

### Architecture

```
tasks.json (source of truth, unchanged)
    ↕
brana-mcp (Rust) — planned per ADR 2026-04-05, exposes task CRUD + queries
    ↕
Next.js web app (new)
├── Kanban board (status swim lanes: pending / in_progress / completed)
├── List/CLI-feel view (sortable by stream, phase, tag, blocked_by)
└── Write operations (direct brana-mcp calls — no CC in the loop)
```

CC chat panel: deferred. Terminal CC stays in terminal for V1. Add chat panel only after
the board has proven its daily use value.

### Why brana-mcp, not CC, as backend

The backlog is JSON. The UI is fundamentally a JSON viewer with write access. brana-mcp
is the correct API surface — fast (<10ms), typed, already planned. A CC layer in the
middle of every drag-and-drop adds 1-2s LLM latency for operations that don't need reasoning.

CC adds value for intelligence operations ("what should I work on?", "triage this sprint").
That stays in the terminal where CC has full context (CLAUDE.md, ruflo, hooks, memory).
A web-embedded CC chat panel would have less context than terminal CC — wrong tradeoff for V1.

## Research Findings

- **Nobody is shipping "CC as backend for task management UI"** — existing CC web UIs
  (`sugyan/claude-code-webui`, `vultuk/claude-code-web`) are CLI wrappers, not Agent SDK backends.
- **Claude Agent SDK is real** — `@anthropic-ai/claude-agent-sdk` (TS) + Python. `query()` for
  one-off prompts, `ClaudeSDKClient` for multi-turn. Viable for a future chat panel.
- **Headless CC** — `claude -p "prompt"` works without TTY. Future option for background
  analysis jobs.
- **Devin / Copilot Workspace pattern**: AI handles planning/validation, human approval is
  explicit. Traditional backend handles execution. This validates the split architecture.
- **brana-mcp ADR (2026-04-05)**: Full Rust, three crates (`brana-core`, `brana-cli`, `brana-mcp`).
  brana-mcp is the planned clean API for all backlog operations.

## Scope

**V1:** thebrana project only. One `tasks.json`, one brana-mcp instance, local-only (localhost:3000).

**Later:** Multi-project portfolio view (clients + ventures). brana-mcp aggregates at startup.
Chat panel backed by Agent SDK when the board has proven its value.

## Risks

| Risk | Mitigation |
|------|-----------|
| brana-mcp not fully shipped | Audit current MCP state before committing to Next.js. May need to ship partial endpoints first. |
| Hosting vs local | Start local-only. Hosted adds auth complexity — not a V1 concern. |
| tasks.json sensitivity | If hosted eventually, brana-mcp needs auth layer. Defer. |
| Kanban model vs tasks.json schema | tasks.json has rich fields. Pick one opinionated Kanban view first. |

## Next Steps

1. **Audit brana-mcp** — what HTTP endpoints exist today vs. what's planned?
2. **ADR** — web layer architecture: local-only, Next.js, brana-mcp transport shape
3. **TDD** — write tests for brana-mcp HTTP endpoints before building Next.js client
4. **Spike** — Next.js app that reads one brana-mcp endpoint and renders a task list
5. **Kanban model design** — map tasks.json fields to board swim lanes
6. **Read-only board first** — add writes after read-only is validated
