# Building Things

The `/brana:build` command handles all development work -- features, bug fixes, refactors, spikes, migrations, investigations, and greenfield projects.

## Quick start

```
/brana:build "JWT authentication for the API"   -- describe what you want
/brana:backlog start t-015                        -- start from an existing task
/brana:build                                     -- asks what to build
```

## How it works

1. **Classify** -- brana detects the work type and confirms with you (mandatory step)
2. **Strategy-specific steps** -- each work type follows a tailored flow
3. **Build** -- test-first implementation with mini-debriefs after each unit
4. **Close** -- retrospective, docs update, task completion

## Work types

| Type | When | Flow |
|------|------|------|
| **Feature** | New capability | SPECIFY -> PLAN -> BUILD -> CLOSE |
| **Bug fix** | Something's broken | REPRODUCE -> DIAGNOSE -> FIX -> CLOSE |
| **Refactor** | Same behavior, better code | SPECIFY (light) -> VERIFY COVERAGE -> BUILD -> CLOSE |
| **Spike** | Need to learn something | QUESTION -> EXPERIMENT -> ANSWER |
| **Migration** | Moving/upgrading systems | SPECIFY -> PLAN -> BUILD (careful) -> CLOSE |
| **Investigation** | Something weird happening | SYMPTOMS -> INVESTIGATE -> REPORT |
| **Greenfield** | New project from scratch | ONBOARD -> SPECIFY -> PLAN -> BUILD -> CLOSE |

## Task integration

`/brana:build` works deeply with `/brana:backlog`:

- `/brana:backlog start <id>` auto-classifies the work type and enters `/brana:build`
- During build, the task's `build_step` field tracks progress (specify/decompose/build/close)
- CLOSE auto-completes the task and updates tasks.json
- Task tags and description seed the research phase

## Related skills

| Skill | How it connects |
|-------|----------------|
| `/brana:backlog start` | Enters build via task selection |
| `/brana:challenge` | Reviews spec during SPECIFY (context-isolated via fork) |
| `/brana:retrospective` | Stores learnings at CLOSE |
| `/brana:docs` | Invoked by CLOSE — generates tech doc, user guide, and shared doc updates |
| `/brana:close` | Session-level close (build's CLOSE is per-task) |

## Key rules

- **CLASSIFY is mandatory** -- always confirmed with user before proceeding
- **TDD always** (except spike) -- tests before implementation
- **You control the pace** during SPECIFY -- brana researches and presents, you decide when to move on
- **Shipped without docs means not shipped** -- every build produces documentation
- **Don't auto-merge** -- user decides when to merge
