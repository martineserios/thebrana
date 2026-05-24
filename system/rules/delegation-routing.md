---
always-load: true
produced_by: docs/architecture/decisions/ADR-040-compute-hierarchy-claude-ruflo-gemini.md
---
# Delegation Routing

## Compute Routing — who runs this? (walk top-to-bottom, first match wins)

```
1. brana-system work? (git, hooks, tasks.json, system/, ruflo stores)
   → Claude only. Never delegate.

2. Atomic, system-isolated, context-enrichable?
   NO → Claude only (needs session state or multi-step).

3. Convention-sensitive? (boilerplate, test scaffolding, ADR drafts, naming for repo output)
   Default: treat as convention-sensitive when in doubt.
   + ruflo available → Gemini (agy_delegate), ENRICH mandatory.
   + ruflo DOWN     → ABORT. Never fall back to unenriched Gemini.

4. Sub-agent needing cost tracking / ownership?
   → ruflo agent_spawn.

5. Parallel, bulk, or token-heavy?
   → Gemini (agy_delegate). ENRICH optional (ruflo down → warn, not abort).

6. Everything else → Claude inline.
```

Gemini output → `/tmp/` only. Claude applies via Write/Edit. See ADR-040.

## Skill Routing — which skill to invoke

Invoke directly — don't suggest. If user declines, don't repeat.
Never invoke a skill AND delegate an agent for the same trigger.

| Trigger | Action |
|---------|--------|
| Work starting (feat/fix/refactor) | check `tasks.json`, then skill routing (`skill-routing.md`) |
| Planning new work | `/brana:backlog add` |
| Session ending | `/brana:close` |
| Big decision forming | `/brana:challenge` |
| New/unfamiliar codebase | `/brana:onboard` |
| Research on a new topic | `/brana:research [topic]` |
| Business health check | `/brana:review check` |
| Weekly/monthly review | `/brana:review` / `/brana:review monthly` |
| Spec changes need impl sync | `/brana:reconcile` |
| Uncommitted spec changes | `/brana:repo-cleanup` |
