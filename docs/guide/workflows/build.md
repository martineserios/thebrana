# Building Things

The `/brana:build` command handles all development work — features, bug fixes, refactors, spikes, migrations, and investigations.

## Quick start

```
/brana:build landing page for tinyhouse    — describe what you want to build
/brana:tasks start t-015                   — start from an existing task
/brana:build                               — ask what to build
```

## How it works

1. **Classify** — brana detects the type of work (feature, bug fix, refactor, etc.) and confirms with you
2. **Strategy-specific steps** — each work type follows a tailored flow
3. **Build** — test-first implementation with mini-debriefs
4. **Close** — retrospective, docs, merge

## Work types

| Type | When | What happens |
|------|------|-------------|
| **Feature** | New capability | Specify → Plan → Build → Close |
| **Bug fix** | Something's broken | Reproduce → Diagnose → Fix → Close |
| **Refactor** | Same behavior, better code | Verify coverage → Build → Close |
| **Spike** | Need to learn something | Question → Experiment → Answer |
| **Migration** | Moving/upgrading systems | Specify → Plan → Build (careful) → Close |
| **Investigation** | Something weird happening | Symptoms → Investigate → Report |
| **Greenfield** | New project from scratch | Onboard → Specify → Plan → Build → Close |

## Task integration

`/brana:build` works deeply with `/brana:tasks`:

- `/brana:tasks start <id>` auto-classifies the work type and enters `/brana:build`
- During build, the task's `build_step` field tracks progress
- CLOSE auto-completes the task and updates tasks.json
- Task tags and description seed the research phase

## Tips

- **Small changes** (1-2 files, obvious fix) skip the heavy steps automatically
- **You control the pace** during SPECIFY — brana researches and presents, you decide when to move on
- Say "draft it" or "let's spec this" when you're ready to write the feature spec
- Every build produces docs — shipped without docs means not shipped
