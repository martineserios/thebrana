# ADR-002: Tasks as JSON Data Layer

**Date:** 2026-02-18
**Status:** proposed

## Context

The brana system needs project planning and task management that works across code and non-code projects, supports hierarchy (phase > milestone > task), integrates with branch strategy, and works through natural language. [Doc 19](../19-pm-system-design.md) designed a GitHub Issues-first PM system that was never built. The current pain: no structured task tracking, no planning visibility, no cross-session state.

Three data layer options were evaluated:
1. Native Claude Code Tasks — metadata doesn't query, session-scoped, insufficient for hierarchy
2. ruflo tasks — agent coordination tool, limited types, no parent-child
3. JSON file per project — full schema control, no N+1, git-tracked, zero dependencies

Constraint: Claude Code subscription only, zero API calls.

## Decision

Use a JSON file per project (`{project}/.claude/tasks.json`) as the single source of truth for task management. Claude Code's intelligence (guided by a convention rule) provides the NL interaction layer. PostToolUse hooks provide deterministic enforcement (schema validation, parent rollup). The /brana:backlog skill provides explicit shortcuts for complex operations.

GitHub Issues sync and markdown rendering are deferred — the JSON schema supports both as future additions (github_issue field, structured hierarchy).

## Consequences

**Easier:**
- Full control over schema — hierarchy, streams, execution modes, tags, context, any field we need
- Zero dependencies — no MCP server, no API calls, no external service
- NL interaction works out of the box — Claude reads rules, reads JSON, responds naturally
- Existing skills gain task awareness with minimal changes
- Future surfaces (markdown, GitHub, dashboard) can read the same JSON

**Harder:**
- No built-in query engine — Claude reads the whole file (mitigated by archiving completed tasks)
- Schema validation depends on hook (mitigated by PostToolUse jq validation)
- Rollup logic depends on hook (mitigated by PostToolUse auto-rollup)
- Git merge conflicts on tasks.json (mitigated by convention: status changes on main only)
- Convention rule adds ~80 lines to always-loaded rules budget

**Schema evolution (v1.1):** `tags` (string[], optional) and `context` (string, optional) fields added post-v1 for flexible classification and rich task background. Both backward-compatible — existing tasks.json files pass validation unchanged. Hook validates types when present.
