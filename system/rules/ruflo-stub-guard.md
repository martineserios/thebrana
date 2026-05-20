---
paths: ["system/procedures/**", "system/skills/**"]
---
# Ruflo Stub Guard

Never use these ruflo commands as authoritative signals. They return hardcoded
or unimplemented output regardless of input:

| Command / Tool | Stub behavior | Safe alternative |
|---|---|---|
| `ruflo security-scan` / `mcp__ruflo__aidefence_scan` | Returns hardcoded fake vulnerability counts | Manual code review; validate.sh |
| `ruflo deploy` | No real implementation; always "succeeds" | `git merge main`; Vercel/Cloud Run deploy |
| Memory quantization output | Reports hardcoded 3.92× compression factor | Treat as display-only; never use in capacity calculations |
| `mcp__ruflo__agentdb_controllers` and all `agentdb_*` (v3.6 additions) | All fail: `AgentDB bridge not available — @claude-flow/memory not installed` | Use `mcp__ruflo__memory_search` + `mcp__ruflo__agentdb_semantic-route` (v3.5 tools — still real) |
| `mcp__ruflo__browser_check` | Checkbox interaction tool — checks/unchecks a DOM element via CSS selector; NOT a browser health check | Use `browser_open` + navigate + inspect result |

**Why:** Confirmed stubs via source audit (issue #1482) and live testing (t-1549,
2026-05-20). Trusting these outputs has caused false security confidence and
incorrect capacity estimates in prior sessions.

**Scope:** This rule applies whenever writing or reviewing procedures and skills
that might reference these tools. For hooks that call ruflo, add a `# STUB — do not trust`
comment next to any of the three patterns above.
