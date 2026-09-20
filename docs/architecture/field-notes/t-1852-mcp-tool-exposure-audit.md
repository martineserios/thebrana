# Field Note: MCP Tool Exposure Audit vs the 10-30 Tool Limit
**Task:** t-1852 | **Date:** 2026-09-20 | **Status:** done

## Question

How many MCP tools are eagerly exposed (in the model's tool list at session start, not deferred behind ToolSearch) in a typical brana session, and is that inside the 10-30 empirical limit (reasoning degrades above ~30 exposed tools; t-781 spike, Swirlai CE 2026)?

## Method

Read-only. Server configuration read from `~/.claude/settings.json` (plugins), `~/.claude.json` (user-scope MCP servers) and the repo `.mcp.json`; eager set confirmed against the tool list of a live session. Names and counts only. Deferred tools do not count: Claude Code auto-defers MCP tools when their descriptions exceed 10% of context, and only servers with `alwaysLoad: true` skip deferral (t-1773).

## Findings

| Server | Source | Loading | Tools | Eager count |
|--------|--------|---------|-------|-------------|
| brana | `.mcp.json`, `alwaysLoad: true` | eager | 24 | **24** |
| ruflo | `.mcp.json` | deferred | ~300 | 0 |
| google-sheets | `~/.claude.json` | deferred | 8 | 0 |
| claude.ai connectors (Drive, Docs, Gmail, Calendar, Notion) | account | deferred | ~30 | 0 |
| claude-in-chrome | plugin/extension | deferred | ~20 | 0 |
| Plugin servers (vercel, supabase, airtable, upstash, linear) | `enabledPlugins` | deferred; unauthenticated ones expose only `authenticate` / `complete_authentication` stubs | few each | 0 |

brana's 24 eager tools: 11 `backlog_*` (add, ac_approve, batch, burndown, focus, get, query, search, set, stale, stats), 6 `backlog_wave_*` (add, approve, drain, get, list, set), 2 `memory_*` (index, write), `recall`, 3 `session_*` (history, read, write), `agy_delegate`.

**Total eagerly exposed MCP tools per typical session: 24.**

## Comparison with the limit

24 is inside the 10-30 band: **under the limit, with 6 tools of headroom.** Total configured tools are well over 300, so the system is only inside the band because of deferred loading; that mechanism is the load-bearing control.

## Mitigation

None required now (count is not over 30). Guardrails to keep it that way:

1. Do not set `alwaysLoad: true` on ruflo or any other large server.
2. brana is the growth risk: it went from ~16 (t-1773) to 24 in three months. At 30 eager tools, either move rarely used groups (`backlog_wave_*`, 6 tools; `backlog_burndown`, `backlog_stale`, `backlog_stats`) to deferred loading by splitting them into a second, non-`alwaysLoad` server, or consolidate verbs (for example one `backlog_wave` tool with an action argument).
3. Re-run this count when adding brana MCP tools; the trigger is 28 or more eager tools.

## Related

- [t-1773 ToolSearch baseline](t-1773-toolsearch-baseline.md)
- [Context Budget Real Limits](../features/context-budget-real-limits.md): records the 10-30 limit as a design constraint
