# ADR-003: Agent-Driven Task Execution

**Date:** 2026-02-18
**Status:** proposed

## Context

The task management system (ADR-002, v1) tracks tasks in `tasks.json` with a dependency DAG via `blocked_by`. Tasks are executed manually — one at a time, by the user invoking `/brana:backlog pick` and `/brana:backlog done`. The DAG already encodes which tasks can run in parallel (siblings with no mutual `blocked_by` edges), but this parallelism is unused.

Claude Code provides native agent spawning: the Task tool for subagents and TeamCreate for multi-agent teams. These can automate multi-task execution — spawn an agent per task, collect results, advance the DAG.

Key constraint: subagents are sandboxed to the project directory and cannot write to worktrees (which live at `../repo-branch-name`). Code tasks that produce file changes need a compose-then-write pattern where agents compose changes and the orchestrator applies them.

## Decision

Extend the task schema with optional agent execution fields and add a `/brana:backlog execute` subcommand that reads the DAG, builds execution waves via topological sort, and spawns subagents to execute tasks in parallel.

### Why subagents over teams

- Tasks are self-contained with clear deliverables (subagent sweet spot)
- Communication is unidirectional: agent reports result, orchestrator decides next step
- ~2x lower token cost than teams (~440K vs ~800K for 3 workers in benchmarks)
- Orchestrator already knows the full DAG — no peer coordination needed
- Teams are experimental with no session resumption; subagents are stable

### Schema extension

Three new optional fields on task objects (`null` = v1 manual behavior):

| Field | Type | Values | Purpose |
|-------|------|--------|---------|
| `spawn` | `string\|null` | `"subagent"`, `"team"`, `null` | How this task executes |
| `agent_config` | `object\|null` | `{type, model}` | Agent type + model routing |
| `agent_result` | `object\|null` | `{status, summary, error, completed_at}` | Outcome after agent finishes |

On parent tasks (phases/milestones), one field controls child execution:

| Field | Type | Values | Purpose |
|-------|------|--------|---------|
| `spawn_strategy` | `string\|null` | `"parallel"`, `"sequential"`, `"auto"`, `null` | How to batch children. `"auto"` reads the DAG. |

All fields are optional and default to `null`. Existing tasks.json files work unchanged — `null` means manual execution (v1 behavior).

### Model routing defaults

| Task characteristic | Model | Rationale |
|---------------------|-------|-----------|
| Research, analysis, exploration | haiku | Fast, cheap, sufficient for information gathering |
| Code implementation, tests | sonnet | Good balance of speed and capability for code |
| Architecture, complex design | opus | User-set only — never auto-assigned |

### `/brana:backlog execute` flow

```
/brana:backlog execute [scope] [--dry-run] [--max-parallel N] [--retry]
```

1. Read tasks.json, identify scope (task/milestone/phase ID, or `"next"`)
2. Build execution waves from `blocked_by` DAG (topological sort)
3. Present plan to user (wave breakdown, agent types, models)
4. User confirms
5. Execute wave-by-wave:
   - Spawn subagents for each task in the wave (up to `--max-parallel`, default 3)
   - Collect results → write `agent_result` to tasks.json
   - Code tasks: queue write-back (compose-then-write pattern)
   - Failed tasks: log error, mark dependents as blocked
6. Write-back phase: apply code task outputs sequentially
7. Report summary

### Code task sandboxing: compose-then-write

```
Agent phase (sandboxed to project dir):
  → Agent reads code, analyzes context, composes changes
  → Writes structured output to /tmp/task-{id}-output.json

Write phase (main context):
  → Reads temp file
  → Creates worktree, applies changes, runs tests, commits
  → Marks task completed or partial
```

Parallel code tasks: agents run in parallel (the expensive part — reading, analyzing, composing), write phases serialize (the cheap part — applying, testing, committing). Acceptable tradeoff.

### Failure handling

| Failure | Response |
|---------|----------|
| Agent timeout | `agent_result.status: "failed"`. Task stays `in_progress`. Dependents blocked. |
| Invalid output | Task reverts to `pending`. User retries or executes manually. |
| Tests fail (code task) | `agent_result.status: "partial"`. User decides: retry or take over. |
| User cancels (Ctrl+C) | In-flight agents terminate. Completed tasks keep status. In-progress revert to `pending`. |

Recovery: `/brana:backlog execute --retry <scope>` re-runs failed/partial tasks, skips completed ones.

### Budget impact

- Convention rule: **0 bytes added** — no changes needed (new fields are optional, pass through validation)
- PostToolUse hook: **no changes** — new fields are extra JSON properties that jq validation ignores
- All agent execution logic lives in SKILL.md (loaded on demand only when `/brana:backlog execute` is invoked)

## Consequences

**Easier:**
- Multi-task execution without manual intervention — spawn agents, collect results, advance DAG
- DAG-aware parallelism — tasks that can run concurrently do run concurrently
- Composable with existing system — v1 manual execution and v2 agent execution coexist
- Model routing keeps costs proportional to task complexity
- Dry-run mode lets users preview execution before committing

**Harder:**
- Agent output quality depends on task description quality — vague tasks produce vague results
- Code task write-back adds a serialization bottleneck (mitigated: agent work is the expensive part)
- Worktree sandbox constraint requires the compose-then-write indirection for code tasks
- Failed agents leave tasks in limbo — user must retry or take over (mitigated: `--retry` flag)
- Token cost scales with task count — a 10-task wave costs ~10x a single task (mitigated: `--max-parallel` cap)
