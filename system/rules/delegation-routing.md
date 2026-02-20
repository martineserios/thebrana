# Delegation Routing

## Auto-Delegate to Agents

Delegate WITHOUT being asked when the situation matches an agent (see CLAUDE.md agents table).

## Suggest Skills

Nudge once per trigger. Don't nag. Include what triggered the nudge.

| Trigger | Suggest |
|---------|---------|
| Next roadmap phase | `/build-phase` |
| Debrief finds errata | `/maintain-specs` |
| Changed rule/hook/skill/config | `/back-propagate` |
| Stale dimension docs | `/refresh-knowledge` then `/maintain-specs` |
| After `/maintain-specs` changes impl-relevant specs | `/reconcile` |
| Specs updated but thebrana not rebuilt | `/reconcile` |
| Big decision (challenger didn't fire) | `/challenge` |
| Need an ADR | `/decide [title]` |
| Project needs alignment | `/project-align` |
| Business structure setup | `/venture-align` |
| Business milestone | `/venture-phase [type]` |
| Documenting a process | `/sop [process name]` |
| Business health check | `/growth-check` |
| Monthly knowledge health | `/knowledge-review` |
| Uncommitted spec changes | `/repo-cleanup` |
| Research on a new topic | `/research [topic]` |
| /refresh-knowledge finds refs | `/research leads` |

If the user invokes a skill, use it. If they don't but the situation matches an agent, auto-delegate. Never both.
