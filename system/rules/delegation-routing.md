# Delegation Routing

## Auto-Delegate to Agents

Delegate WITHOUT being asked when the situation matches an agent (see CLAUDE.md agents table).

## Suggest Skills

Nudge once per trigger. Don't nag. Include what triggered the nudge.

| Trigger | Suggest |
|---------|---------|
| Work starting (feat/fix/refactor) | check `tasks.json` |
| Next roadmap phase | `/build-phase` |
| Debrief finds errata | `/maintain-specs` |
| Changed rule/hook/skill/config | `/back-propagate` |
| Stale dimension docs | `/refresh-knowledge` then `/maintain-specs` |
| After `/maintain-specs` changes impl-relevant specs | `/reconcile` |
| After `/maintain-specs` cascades across docs | `/memory review --audit` (touched docs only) |
| Specs updated but thebrana not rebuilt | `/reconcile` |
| Big decision (challenger didn't fire) | `/challenge` |
| Need an ADR | `/decide [title]` |
| Project needs alignment | `/project-align` |
| Business structure setup | `/venture-align` |
| Business milestone | `/venture-phase [type]` |
| Documenting a process | `/sop [process name]` |
| Business health check | `/growth-check` |
| Monthly knowledge health | `/memory review` |
| Uncommitted spec changes | `/repo-cleanup` |
| Research on a new topic | `/research [topic]` |
| /refresh-knowledge finds refs | `/research leads` |
| Planning new work | `/tasks plan` or `/tasks add` |
| Backlog item picked to implement | `/build-feature` (ADR → SDD → TDD) |
| New task added with URL or platform name | brief research before priority |
| New research task added (stream=research) | tag matching against pending non-research tasks |
| Monthly or after `/growth-check` | `/tasks reprioritize --reresearch` |
| Session ending (user says done/bye/closing) | `/session-handoff` |

If the user invokes a skill, use it. If they don't but the situation matches an agent, auto-delegate. Never both.
