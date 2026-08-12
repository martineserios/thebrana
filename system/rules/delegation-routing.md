---
always-load: true
produced_by: docs/architecture/decisions/ADR-059-multi-agent-substrate-selection.md
supersedes: ADR-040 (Gemini-first routing, retired 2026-06-19)
---
# Delegation Routing

## Compute Routing — who runs this? (walk top-to-bottom, first match wins)

```
1. brana-system (git, hooks, tasks.json, system/, ruflo stores) → Claude only, never delegate.
2. In-session multi-agent, structured (find→verify→synthesize, judge-panel) → native WORKFLOW (.claude/workflows/).
3. In-session quick parallel fan-out → native TASK (Agent tool), many agents per message.
4. Atomic / detail retrieval, ZERO reasoning → claude -p --model haiku (subscription, no quota).
5. Cross-model second opinion — CHALLENGER ONLY → agy (Gemini); quota exhausted → Claude challenger lens. The ONLY use of agy.
6. Autonomous / overnight / "until all done" → native /loop + claude -p over tasks.json, or ruflo autopilot (see ADR-059).
7. Cross-session recall → `brana recall` / `mcp__brana__recall`, NOT `mcp__ruflo__memory_search` (t-2294).
8. Everything else → Claude inline.
```

**Never** use ruflo MCP `agent_execute`/`hive-mind_*`/`coordination_*` for execution — hollow under subscription (records + self-votes). **Never** use `mcp__ruflo__wasm_agent_prompt` — under no API key it returns a literal `echo: <input>` stub that looks like a real answer (live-probed 2026-08-12; on this install it errors before even that — optional pkg missing). **Never** use `mcp__ruflo__terminal_execute` — unrestricted shell via MCP with no permission prompt (also denied in settings, t-2755). Exception: `mcp__ruflo__testgen_tdd_repair` IS sanctioned — the one subscription-native ruflo MCP execution path (spawns `claude -p`, budget-capped, test-verified); branch on `data.repaired`, never `success` (verify availability on installed version first — confirmed at HEAD v3.38, unverified on v3.34, t-2753). See `field-note_ruflo-agentic-layer-subscription-theater`, ADR-059.

**t-2759 additions** (2026-08-12, see `ruflo-mcp-tool-classification.md`): AgentDB bridge breaks `agentdb_context-synthesize`/`batch`/`feedback`/`session-start`/`-end`/`consolidate`. `agentdb_pattern-search`/`route` degrade silently — use `memory_search(namespace:"pattern")`. Never trust `performance_metrics` — use `performance_bottleneck`. `guidance_recommend` suggests forbidden tools — verify against this file. `task_summary` contradicts `task_list` — trust `task_list`. `wasm_gallery_*`/`ruvllm_chat_format`/`generate_config` are BROKEN (missing deps).

Headless output (`claude -p`, agy) → `/tmp/` only; Claude applies via Write/Edit (cwd-discipline.md). agy never runs git.

## Retrieval (ADR-064)

"What calls X"/impact/path queries → `graphify` CLI if `graphify-out/graph.json` exists; open-ended → Explore; decisions → recall. Table: retrieval-routing.md.

## Skill Routing — which skill to invoke

Invoke directly, don't suggest; if declined, don't repeat. Never invoke a skill AND delegate for one trigger.

| Trigger | Action |
|---------|--------|
| Work starting (feat/fix/refactor) | follow `work-start.md` ordered entry protocol |
| Planning new work | `/brana:backlog add` |
| Session ending | `/brana:close` |
| Big decision forming | `/brana:challenge` |
| Deep adversarial review (high-stakes) | `/brana:challenge --deep` (native fan-out + verify-findings) |
| New/unfamiliar codebase | `/brana:onboard` |
| Research on a new topic | `/brana:research [topic]` |
| Business health check | `/brana:review check` |
| Weekly/monthly review | `/brana:review` / `/brana:review monthly` |
| Spec changes need impl sync | `/brana:reconcile` |
| Uncommitted spec changes | `/brana:repo-cleanup` |
