---
name: build
description: "Build anything — features, bug fixes, refactors, spikes, migrations. Auto-detects strategy, integrates with backlog, enforces TDD. The unified dev command."
effort: high
model: sonnet
keywords: [development, implementation, tdd, feature, bug-fix, refactor, coding, fix, broken, hook, deploy, test, debug, error, crash, migrate, investigate]
task_strategies: [feature, bug-fix, refactor, spike, greenfield, migration, investigation]
stream_affinity: [roadmap, bugs, tech-debt, experiments]
argument-hint: "[decompose] [description or task ID]"
group: execution
depends_on:
  - backlog
  - challenge
  - retrospective
allowed-tools:
  - Agent
  - AskUserQuestion
  - Bash
  - Edit
  - EnterPlanMode
  - Glob
  - Grep
  - Read
  - Skill
  - Task
  - TaskCreate
  - TaskList
  - TaskUpdate
  - WebFetch
  - WebSearch
  - Write
  - mcp__ruflo__hive-mind_memory
  - mcp__ruflo__memory_search
  - mcp__ruflo__memory_store
  - mcp__ruflo__agent_spawn
  - mcp__ruflo__claims_claim
  - mcp__ruflo__claims_release
  - ToolSearch
status: stable
growth_stage: evergreen
---

# Build

The unified development command. One entry point for all work types: features, bug fixes, greenfield projects, refactors, spikes, migrations, and investigations. Auto-detects the right strategy, integrates deeply with `/brana:backlog`, and enforces TDD throughout.

## Phase Protocol — how to execute this skill

The procedure body lives in per-phase files under `phases/` (this skill's base directory — the path announced when the skill loads). **Never execute a phase from memory.** Three rules:

1. **On skill entry:** Read `phases/load.md` first — always, before anything else.
2. **At every step boundary:** when a phase completes and the next begins, Read the next phase file from the PHASES registry below BEFORE doing any of its work. A phase you have not Read this session does not exist — do not improvise its steps from the overview or from training data.
3. **On resume after compression:** identify your current step (CC TaskList `/brana:build — {STEP}` entries, or the task's `build_step` field via `brana backlog get {id}`), then Read that step's phase file before continuing. The previously loaded phase content did NOT survive compression. Also re-read `../_shared/guided-execution.md` if a step registry is in play.

<!-- PHASES -->
| Step | File | Load when |
|------|------|-----------|
| LOAD + CROSS-REFERENCE + STEP REGISTRY + RESUME CHECK + READINESS | phases/load.md | Skill entry — always first |
| CLASSIFY + APPROVE (+ task integration) | phases/classify.md | After LOAD completes |
| Decompose mode | phases/decompose-mode.md | Only when invoked as `/brana:build decompose` |
| SPECIFY (feature / greenfield / migration) | phases/specify.md | Strategy confirmed as feature, greenfield, or migration |
| DECOMPOSE | phases/decompose.md | SPECIFY artifacts approved |
| BUILD loop | phases/build-loop.md | Entering the build/fix implementation loop (any strategy) |
| Verification gates (ISC, BUILD→CLOSE, Four Questions, Docs, Evaluator, Challenger) | phases/verify-gates.md | BUILD subtasks complete, before CLOSE |
| Strategy variants (bug fix, greenfield, refactor, spike, migration, investigation) | phases/strategies.md | Strategy confirmed as anything other than feature |
| Auto-learning (EXTRACT → EVALUATE → PERSIST) | phases/learning.md | After gates pass (before CLOSE / REPORT / ANSWER) |
| CLOSE | phases/close.md | After auto-learning — feature, bug fix, greenfield, refactor, migration (not spike/investigation) |
<!-- /PHASES -->

In the deployed-plugin layout the same relative paths apply: `{base-dir}/phases/{file}`. If a path doesn't resolve, use Glob: `**/skills/build/phases/{file}`.

## Lifecycle context

Build implements the brana development workflow defined in [docs/reflections/32-lifecycle.md](../../../docs/reflections/32-lifecycle.md): **DDD → SDD → TDD → Code**.

| Build step | Lifecycle phase | What it produces |
|---|---|---|
| SPECIFY | DDD (when `docs/domain/` exists) + SDD | Domain glossary updates, ADR(s), feature spec |
| DECOMPOSE | SDD continuation | Ordered task tree with acceptance criteria |
| BUILD | TDD | Failing test → implementation → refactor, per subtask |
| EXTRACT/EVALUATE/PERSIST | Continuous learning | Patterns, ADRs, field notes |

DDD is strategic (judgment), SDD is tactical (decisions), TDD is mechanical (red-green-refactor). DDD enforcement activates when `docs/domain/` exists in the project (same opt-in pattern as SDD's `docs/decisions/`).

## Invocation

```
/brana:build "description"              — start from a description
/brana:build                            — ask what to build
/brana:build decompose "description"    — decompose work into a task tree (phase/milestone/task/subtask)
/brana:build decompose <id>            — decompose an existing task into subtasks
```

Also entered via `/brana:backlog start <id>` for code tasks — see Task Integration in `phases/classify.md`.

## Flow overview

| Strategy | Step sequence |
|----------|--------------|
| Feature | LOAD → CLASSIFY → APPROVE → SPECIFY → DECOMPOSE → BUILD → gates → learning → CLOSE |
| Bug fix | LOAD → CLASSIFY → REPRODUCE → DIAGNOSE → FIX → gates → learning → CLOSE |
| Greenfield | LOAD → CLASSIFY → ONBOARD → SPECIFY → DECOMPOSE → BUILD → gates → learning → CLOSE |
| Refactor | LOAD → CLASSIFY → SPECIFY (light) → VERIFY COVERAGE → BUILD → gates → learning → CLOSE |
| Spike | LOAD → CLASSIFY → QUESTION → EXPERIMENT → learning → ANSWER |
| Migration | LOAD → CLASSIFY → SPECIFY → DECOMPOSE → BUILD (careful) → gates → learning → CLOSE |
| Investigation | LOAD → CLASSIFY → SYMPTOMS → INVESTIGATE → learning → REPORT |

Strategy variants (everything except the feature path) are detailed in `phases/strategies.md`; the shared BUILD loop, gates, learning, and CLOSE are in their own phase files.

## Task Operations — MANDATORY

**NEVER read or write tasks.json directly.** No `cat tasks.json`, no `uv run python` parsing, no `Read` tool on tasks.json.

**Prefer MCP tools** (brana server) when available — they return structured JSON with 65% fewer tokens than CLI:
- **Read:** `backlog_get(task_id)`, `backlog_query(status, tag, stream, ...)`, `backlog_search(query)`
- **Write:** `backlog_set(task_id, field, value)`, `backlog_add(subject, stream, ...)`
- **Browse:** `backlog_stats()`

**Fallback to CLI** via Bash if MCP tools are unavailable:
- **Read:** `brana backlog get <id>`, `brana backlog query --status pending`, `brana backlog search "keyword"`, `brana backlog next`
- **Write:** `brana backlog set <id> <field> <value>`, `brana backlog add --json '{...}'`
- **Browse:** `brana backlog stats`, `brana backlog tags`, `brana backlog roadmap`

This applies to EVERY step — CLASSIFY, SPECIFY, DECOMPOSE, BUILD, CLOSE. No exceptions.

## Sizing heuristics

The strategy adapts not just by type but by size. These heuristics determine how much of each step to do:

| Size | Signal | SPECIFY depth | DECOMPOSE detail | Enforcement gates |
|------|--------|--------------|-------------------|-------------------|
| **Trivial** | 1 file, obvious fix | Skip SPECIFY | No decomposition | None |
| **Small** | 1-3 files, scope clear | Light (no research) | Inline — no separate step | None |
| **Medium** | 4+ files, design needed | Full research loop | Full task breakdown | Hard gates at transitions |
| **Large** | New skill/system, unknown scope | Deep research + challenger | Full + dependencies | Hard gates at transitions |

Claude proposes the size. User can override: "this is bigger than it looks" or "just do it, it's simple."

## Rules

1. **CLASSIFY is mandatory.** Uses the 2-level smart router (signal → ask). Never skip the confirmation step. Never silently apply a strategy.
2. **TDD always** (except spike). Write the test before the code. The PreToolUse hook enforces this on feat/* branches.
3. **User controls pace in SPECIFY.** Never auto-advance from research to draft. Wait for the signal.
4. **Challenger is context-isolated.** Always spawn a separate agent for the challenger review. Never self-review.
5. **Shipped without docs means not shipped.** CLOSE generates tech doc + user guide from templates (feature/greenfield/migration). Refactors get tech doc only if architecture changed. Bug fixes skip docs.
6. **Don't auto-merge.** Present the merge command. Let the user decide.
7. **Mid-stream reclassification is allowed.** The user can change strategy at any point. Carry forward what's been learned.
8. **Mini-debrief after every task in BUILD.** 30 seconds. What surprised? Pattern? Don't skip.
9. **Cross-reference before creating work.** Always check for related tasks first (unless entering via /brana:backlog start).
10. **Graceful degradation.** If ruflo is unavailable, use auto memory. If no test framework, note it and proceed. If no GitHub Issues, use tasks.json.
11. **Step registry for Medium/Large builds.** Follow the [guided-execution protocol](../_shared/guided-execution.md). Skip for Trivial/Small.
12. **Phase files are the procedure.** Read the registered phase file at every step boundary (Phase Protocol above). Never run a step from the overview alone.

## Resume After Compression

If context was compressed and you've lost track of progress:

1. Call `TaskList` — find all CC Tasks matching `/brana:build`
2. **Filter by level:**
   - **Step-level** tasks match `/brana:build — {STEP}` (CLASSIFY, SPECIFY, DECOMPOSE, BUILD, CLOSE)
   - **Subtask-level** tasks match `/brana:build — BUILD/subtask: {name}`
3. Find the `in_progress` step-level task — that's your current build step
4. If in BUILD step: find the `in_progress` subtask — that's your current subtask
5. If no `in_progress` at either level, find the first `pending` with all blockers `completed`
6. Use the task description and `build_step` field in tasks.json for additional context
7. **Read the current step's phase file** (PHASES registry above) before executing anything — the phase content loaded before compression is gone.
