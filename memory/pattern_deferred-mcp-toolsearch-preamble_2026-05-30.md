---
name: deferred-mcp-toolsearch-preamble
description: Deferred MCP tool schemas require ToolSearch before invocation — missing preamble causes silent InputValidationError in all procedures
metadata:
  type: feedback
---

All `mcp__<server>__<tool>()` calls in procedures fail silently when the tool schema hasn't been loaded. CC defers MCP tool schemas at session start — calling them directly throws `InputValidationError`. Every procedure that uses ruflo (or any other MCP server with deferred tools) needs a `<!-- ruflo preamble -->` block loading exact schemas via `ToolSearch("select:...")` before the first call.

**Why:** Discovered in t-1766 brainstorm — 13 brana procedures had ruflo calls that had never fired in practice. The silent fallback path masked the error completely.

**How to apply:** Add to top of first ruflo-using step in each procedure:
```
<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__tool1,mcp__ruflo__tool2")
```
`validate.sh` Check 36 enforces this — any procedure with `mcp__ruflo__` calls without the preamble comment fails lint. Scope: cross-project — applies to any CC project with deferred MCP tools.
