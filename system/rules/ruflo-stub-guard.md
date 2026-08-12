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
| `mcp__ruflo__agentdb_controllers`, `agentdb_semantic-route`, `agentdb_health`, `agentdb_hierarchical-store/recall/delete`, `agentdb_context-synthesize`, `agentdb_batch`, `agentdb_feedback`, `agentdb_session-start/-end`, `agentdb_consolidate` | Fail with `AgentDB bridge not available`. Root cause confirmed 2026-08-12 (t-2757): installed `@claude-flow/memory` double-exports `ControllerRegistry`, crashing the bridge on import — a packaging bug, fixed upstream (not in our pinned version), not a "v3.5 vs v3.6" split. **NOT all `agentdb_*` tools** — `graph-query`/`graph-pathfinder`/`causal-edge*` use a separate `graph-node` backend and work (t-2759, live-probed 2026-08-12); corrected from an earlier "all `agentdb_*`" overstatement. | Use `mcp__ruflo__memory_search` / `memory_store` instead |
| `mcp__ruflo__agentdb_pattern-search`, `mcp__ruflo__agentdb_route` | Do NOT error — silently degrade to a fallback (substring match; hardcoded `confidence:0.5`) instead of the advertised ReasoningBank/semantic behavior. Worse than a stub because the output looks legitimate (t-2759, live-probed 2026-08-12). | `memory_search(namespace:"pattern")` for pattern lookup; do not trust `agentdb_route`'s recommendation |
| `mcp__ruflo__performance_metrics` | Self-labels `"_real": false` in its own payload. | `mcp__ruflo__performance_bottleneck` (same family, `"_real": true`, genuinely computed) |
| `mcp__ruflo__browser_check` | Checkbox interaction tool — checks/unchecks a DOM element via CSS selector; NOT a browser health check | Use `browser_open` + navigate + inspect result |
| `mcp__ruflo__guidance_recommend` | Genuinely scores the input task, but its recommended execution steps include forbidden/dead tools (`agent_spawn`, `terminal_execute`) — the recommender hasn't been updated for ADR-059/t-2755 routing rules (t-2759, live-probed 2026-08-12) | Cross-check any suggestion against `delegation-routing.md` before following it |
| `mcp__ruflo__task_summary` | Undercounts live state — reported `running:0` in the same session where `mcp__ruflo__task_list` showed a task with `status:"running"` (t-2759, live-probed 2026-08-12) | Use `mcp__ruflo__task_list` directly, not the summary rollup |

**Why:** Confirmed stubs via source audit (issue #1482) and live testing (t-1549,
2026-05-20). Trusting these outputs has caused false security confidence and
incorrect capacity estimates in prior sessions.

**Scope:** This rule applies whenever writing or reviewing procedures and skills
that might reference these tools. For hooks that call ruflo, add a `# STUB — do not trust`
comment next to any of the three patterns above.
