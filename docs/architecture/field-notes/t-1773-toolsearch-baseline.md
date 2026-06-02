# Field Note: MCP Tool Search Empirical Baseline
**Task:** t-1773 | **Date:** 2026-06-02 | **Status:** done

## Findings

### ToolSearch preamble overhead (current state)

Every skill procedure that touches ruflo or brana MCP tools carries a manual `ToolSearch(select:...)` preamble to load deferred schemas. Counts across 15 skill procedures:

| Procedure | ToolSearch calls |
|-----------|-----------------|
| backlog.md | 14 |
| build.md | 12 |
| brainstorm.md | 11 |
| research.md | 10 |
| review.md | 9 |
| close.md | 9 |
| gsheets.md | 8 |
| ship.md | 6 |
| gemini.md | 6 |
| sitrep.md | 5 |

### Most-called ruflo tools (candidates for alwaysLoad)

| Tool | Preamble refs | Total refs | Every-session? |
|------|--------------|------------|----------------|
| mcp__ruflo__memory_search | 9 | 38 | yes |
| mcp__ruflo__memory_store | 6 | 22 | yes |
| mcp__ruflo__agent_spawn | 5 | 10 | multi-agent flows |
| mcp__brana__agy_delegate | 3 | — | research/gemini |

### brana MCP tool inventory (~16 tools, all session-relevant)

`backlog_add`, `backlog_batch`, `backlog_burndown`, `backlog_focus`, `backlog_get`, `backlog_query`, `backlog_search`, `backlog_set`, `backlog_stale`, `backlog_stats`, `agy_delegate`, `memory_index`, `memory_write`, `session_history`, `session_read`, `session_write`

### Key CC feature confirmed: `alwaysLoad`

CC v2.1.x added `alwaysLoad: true` to MCP server config. When set, all tools from that server skip deferral and are available at session start without ToolSearch. Also confirmed: auto-defer mode fires when MCP tool descriptions exceed 10% of context window.

## Recommendation for t-1777

**Set `alwaysLoad: true` on the brana server only.**

- brana has ~16 tools, all used regularly, small schemas — low context cost
- ruflo has 200+ tools — alwaysLoad would blow the context budget; keep deferred
- With brana always loaded, remove `mcp__brana__*` from all ToolSearch preambles in skill procedures

**Do not** set `alwaysLoad: true` on ruflo. Auto-defer + targeted ToolSearch selects is correct for ruflo given its tool count. The top 3 ruflo tools (memory_search, memory_store, agent_spawn) justify staying in preambles since they're called selectively, not on every skill.

## Pass condition met

Data collected. alwaysLoad confirmed. brana server identified as the right target. t-1777 unblocked.
