# Delegation Routing

## Auto-Delegate to Agents

Delegate WITHOUT being asked when the situation matches an agent (see CLAUDE.md agents table).

## Use Skills Directly

When a trigger matches, **invoke the skill** — don't just suggest it. Only nudge when the match is ambiguous or the user is mid-flow. If the user declines, don't repeat.

| Trigger | Action |
|---------|--------|
| Work starting (feat/fix/refactor) | check `tasks.json`, then `/brana:build` |
| Planning new work | `/brana:backlog plan` or `/brana:backlog add` |
| Backlog item picked to implement | `/brana:backlog start` → `/brana:build` |
| Session ending (user says done/bye/closing) | `/brana:close` |
| Big decision (challenger didn't fire) | `/brana:challenge` |
| New project or unfamiliar codebase | `/brana:onboard` |
| Project needs structural alignment | `/brana:align` |
| Business milestone | `/brana:venture-phase [type]` |
| Business health check | `/brana:review check` |
| Weekly review | `/brana:review` |
| Monthly close + forward plan | `/brana:review monthly` |
| Research on a new topic | `/brana:research [topic]` |
| Stale dimension docs | `/brana:research --refresh` then `/brana:maintain-specs` |
| After `/brana:maintain-specs` changes impl-relevant specs | `/brana:reconcile` |
| After `/brana:maintain-specs` cascades across docs | `/brana:memory review --audit` (touched docs only) |
| Specs updated but thebrana not rebuilt | `/brana:reconcile` |
| Monthly knowledge health | `/brana:memory review` |
| Uncommitted spec changes | `/brana:repo-cleanup` |
| New task added with URL or platform name | brief research before priority |
| New research task added (stream=research) | tag matching against pending non-research tasks |
| Monthly or after `/brana:review check` | `/brana:backlog triage --reresearch` |

If the user invokes a skill, use it. If they don't but the situation matches an agent, auto-delegate. Never both.
