---
always-load: true
---
# Skill Routing

Before starting any implementation, design, or research work — **always ask** which skills to load. Never silently route. Excessive asking is correct; silent routing is not.

## Two layers for every task

- **Workflow skill** — HOW to work: `build`, `research`, `align`, `reconcile`
- **Domain skill** — WHAT rules to follow: any installed domain skill (e.g. `rust-skills`), or `acquire-skills` if none matches

| Work type | Workflow skill |
|-----------|---------------|
| Implementation (feature, fix, refactor) | `build` |
| Research, investigation, comparison | `research` |
| Architecture, alignment, conventions | `align` |
| Spec/doc maintenance | `reconcile` or `verify-docs` |
| Drift, security, sync | `reconcile` |

Domain skills: run `brana skills suggest --query "<domain>"` to find installed matches. No match → offer `acquire-skills`.

## Gate: always ask before loading

Use AskUserQuestion to present detected workflow + domain skill and ask for confirmation. Options: workflow only / domain only / both (default) / skip. If domain is ambiguous, ask that first.

## Rules

- **Always ask.** Never silently invoke a skill for work that hasn't been confirmed.
- **Suggest both layers as default** when a domain skill is installed.
- **No double-loading.** Skip the ask if the skill was already loaded this session for this task.
- **Surface gaps.** No domain skill → always offer `acquire-skills`, don't skip silently.
- **Overrides delegation-routing.** "Work starting → ask first via skill routing, then invoke confirmed skill."
