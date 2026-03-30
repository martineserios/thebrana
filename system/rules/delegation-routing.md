# Delegation Routing

Delegate to agents WITHOUT being asked when context matches (see CLAUDE.md agents table). Invoke skills directly — don't suggest them. If user declines, don't repeat.

| Trigger | Action |
|---------|--------|
| Work starting (feat/fix/refactor) | check `tasks.json`, then `/brana:build` |
| Planning new work | `/brana:backlog add` |
| Session ending (done/bye/closing) | `/brana:close` |
| Big decision forming | `/brana:challenge` |
| New/unfamiliar codebase | `/brana:onboard` |
| Research on a new topic | `/brana:research [topic]` |
| Business health check | `/brana:review check` |
| Weekly/monthly review | `/brana:review` / `/brana:review monthly` |
| Spec changes need impl sync | `/brana:reconcile` |
| Uncommitted spec changes | `/brana:repo-cleanup` |

Never invoke a skill AND delegate to an agent for the same trigger.

```
Example — user says "let's add webhook support"

  1. Check tasks.json → no existing task → propose one
  2. Trigger: "work starting" → invoke /brana:build (don't suggest it)
  3. During PLAN step: challenger agent auto-fires (plan forming)
  4. User says "I'm done for today" → invoke /brana:close

  WRONG: suggest "/brana:build" instead of invoking it
  WRONG: fire challenger AND suggest /brana:challenge
```
