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
| **Feature** | New capability | SPECIFY -> DECOMPOSE -> BUILD -> CLOSE |
| **Bug fix** | Something's broken | REPRODUCE -> DIAGNOSE -> FIX -> CLOSE |
| **Refactor** | Same behavior, better code | SPECIFY (light) -> VERIFY COVERAGE -> BUILD -> CLOSE |
| **Spike** | Need to learn something | QUESTION -> EXPERIMENT -> ANSWER |
| **Migration** | Moving/upgrading systems | SPECIFY -> DECOMPOSE -> BUILD (careful) -> CLOSE |
| **Investigation** | Something weird happening | SYMPTOMS -> INVESTIGATE -> REPORT |
| **Greenfield** | New project from scratch | ONBOARD -> SPECIFY -> DECOMPOSE -> BUILD -> CLOSE |

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
| `/brana:fix` | Focused bug-fix flow: REPRODUCE → DIAGNOSE → FIX → VERIFY → COMMIT. Use when you know it's a bug and want a tighter loop than `/brana:build`. |

## Evaluator gate

Before the Challenger, a separate `build-evaluator` agent grades the implementation against your task's `AC:` lines. This is an objective pass/fail check — did you build what the spec said?

**When it runs:** automatically when the task has `acceptance_criteria` (the canonical field) or `AC:` lines in context. Skipped silently otherwise. Tasks planned via `/brana:backlog plan` get criteria auto-generated, so this gate usually activates without hand-writing anything.

**Verdicts:**
- **PASS** — all criteria met; proceeds to Challenger Gate
- **PASS WITH GAPS** — some criteria partial; warns but proceeds
- **FAIL** — one or more criteria MISSED; blocks CLOSE (max 2 repair iterations, same pattern as Challenger)

Criteria come from planning (auto-generated) or `AC:` lines written during SPECIFY; `AC:` lines normalize into the `acceptance_criteria` field on first build. See [AC: syntax](../../conventions/ac-criteria.md) for the user-facing forms and [ac-grammar.md](../../architecture/ac-grammar.md) for the canonical heuristic grammar.

---

## Challenger gate

Before CLOSE, an independent Challenger agent reviews the implementation against the spec. This is separate from the `/brana:challenge` invocation during SPECIFY — it's a mandatory BUILD exit review.

**When it runs:**

| Situation | Behavior |
|---|---|
| M+ effort task | Runs automatically — no prompt |
| Any task touching `system/`, `.claude/hooks/`, or `docs/architecture/decisions/` | Runs automatically |
| S-effort, regular paths | Prompt appears, default is "Run Challenger" |
| Spike or investigation | Skipped |

**What it reviews:**
- Are all acceptance criteria met? (from task context `AC:` lines)
- Does the diff match the spec — no scope creep or miss?
- Any security antipatterns?

Challenger reads only trusted content: the task spec, the git diff, and the AC list. It never reads raw web responses or external API output.

**When it blocks:**
A finding scored 4 or higher (WARNING/CRITICAL per [CALIBRATION.md](../../architecture/agents/CALIBRATION.md)) returns verdict `RECONSIDER` and blocks CLOSE. You get three choices:
- **Fix now** — findings are saved to the task context and BUILD re-runs; Challenger reviews again (max 2 passes)
- **Override** — provide a reason; it's logged and CLOSE proceeds
- **Abandon** — task marked blocked

**Key rules:**

- **CLASSIFY is mandatory** -- always confirmed with user before proceeding
- **TDD always** (except spike) -- tests before implementation
- **You control the pace** during SPECIFY -- brana researches and presents, you decide when to move on
- **Shipped without docs means not shipped** -- every build produces documentation
- **Challenger gate before every CLOSE** -- independent semantic review, not just structural validation
- **Don't auto-merge** -- user decides when to merge
