# Delegation Routing

## Auto-Delegate to Agents

Delegate WITHOUT being asked when the situation matches an agent (see CLAUDE.md agents table).

## Use Skills Directly

When a trigger matches, **invoke the skill** — don't just suggest it. Only nudge when the match is ambiguous or the user is mid-flow. If the user declines, don't repeat.

| Trigger | Action |
|---------|--------|
| Work starting (feat/fix/refactor) | check `tasks.json`, then `/build` |
| Planning new work | `/tasks plan` or `/tasks add` |
| Backlog item picked to implement | `/tasks start` → `/build` |
| Session ending (user says done/bye/closing) | `/close` |
| Big decision (challenger didn't fire) | `/challenge` |
| New project or unfamiliar codebase | `/onboard` |
| Project needs structural alignment | `/align` |
| Business milestone | `/venture-phase [type]` |
| Business health check | `/review check` |
| Weekly review | `/review` |
| Monthly close + forward plan | `/review monthly` |
| Research on a new topic | `/research [topic]` |
| Stale dimension docs | `/research --refresh` then `/maintain-specs` |
| After `/maintain-specs` changes impl-relevant specs | `/reconcile` |
| After `/maintain-specs` cascades across docs | `/memory review --audit` (touched docs only) |
| Specs updated but thebrana not rebuilt | `/reconcile` |
| Monthly knowledge health | `/memory review` |
| Uncommitted spec changes | `/repo-cleanup` |
| New task added with URL or platform name | brief research before priority |
| New research task added (stream=research) | tag matching against pending non-research tasks |
| Monthly or after `/review check` | `/tasks reprioritize --reresearch` |

If the user invokes a skill, use it. If they don't but the situation matches an agent, auto-delegate. Never both.
