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
6. Autonomous / overnight / "until all done" → native /loop + claude -p over tasks.json.
7. Cross-session recall → `brana recall` / `mcp__brana__recall`, NOT `mcp__ruflo__memory_search` (t-2294).
8. Everything else → Claude inline.
```

**Never** use ruflo MCP `agent_execute`/`hive-mind_*`/`coordination_*` for execution — hollow under subscription (records + self-votes). **Never** use `mcp__ruflo__wasm_agent_prompt` — under no API key it returns a literal `echo: <input>` stub (this install errors even earlier — optional pkg missing). **Never** use `mcp__ruflo__terminal_execute` — unrestricted shell via MCP, no permission prompt (denied in settings, t-2755). No sanctioned ruflo MCP execution path exists: `testgen_tdd_repair` is a dead export, never registered on v3.34 or v3.38.3 — use `/brana:build`'s TDD loop instead (t-2753). CLI `--claude` spawn (no worktree isolation) and the Meta LLM Proxy (absent on our pinned version) are also closed (t-2763) — ruflo's sanctioned surface is memory/recall only. See `field-note_ruflo-agentic-layer-subscription-theater`, ADR-059.

**t-2759**: more AgentDB/performance/guidance/wasm findings — see `ruflo-mcp-tool-classification.md`.

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
