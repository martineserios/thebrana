<!-- backlog phase: /brana:backlog execute — DAG-aware subagent execution, model routing — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__claims_claim,mcp__ruflo__claims_mark-stealable,mcp__ruflo__claims_release,mcp__ruflo__memory_search")

## /brana:backlog execute

Execute tasks via subagents — DAG-aware parallel execution with automatic batch scheduling.

```
/brana:backlog execute [scope] [--dry-run] [--max-parallel N] [--retry]
```

**Arguments:**
- `scope`: task/milestone/phase ID, or `"next"` for the next unblocked batch. Default: next
- `--dry-run`: show execution plan without running agents
- `--max-parallel N`: max concurrent subagents per batch (default: 3)
- `--retry`: re-run failed/partial tasks, skip completed

### Prerequisites

Tasks must have `spawn` field set (see ADR-003 for schema). Tasks without `spawn` are skipped with a message: "no tasks configured for agent execution."

### Steps

1. **Read tasks.json**, identify scope
2. **Filter executable tasks** — only tasks with `spawn: "subagent"` and status `pending` (or `in_progress`/failed for `--retry`)
3. **Build execution batches** from `blocked_by` DAG (topological sort):
   - Batch 1: tasks with no unmet dependencies
   - Batch 2: tasks whose blockers are all in batch 1
   - Batch N: tasks whose blockers are all in earlier batches
4. **Check parent `spawn_strategy`** — if set, override batch ordering:
   - `"parallel"`: all children in one batch (ignore inter-child deps)
   - `"sequential"`: one task per batch, in order
   - `"auto"`: use DAG (default behavior)
5. **Present execution plan:**
   ```
   Execution plan for ph-002 (3 batches, 8 tasks):

     Batch 1 (parallel):
       t-007 Design auth flow          haiku   research
       t-010 Design schema             haiku   research

     Batch 2 (parallel):
       t-008 Implement JWT middleware   sonnet  code
       t-011 Write migrations           sonnet  code

     Batch 3 (parallel):
       t-009 Write auth tests           sonnet  code
       t-012 Seed dev data              sonnet  code

   Estimated: 3 batches, max 2 parallel agents per batch.
   Proceed? (yes / dry-run was requested)
   ```
6. **User confirms**
7. **Execute batch-by-batch:**

   **7a. Batch ID** (once per execute run, before first batch):
   Derive a local batch identifier for claim ownership — no ruflo call needed (`swarm_init` is bookkeeping-only under subscription, ADR-059; it never created a real topology to init):
   ```
   swarmId = "{git branch --show-current}-{execute run timestamp}"
   ```

   - **Knowledge injection (per task, before spawning):**
     Query ruflo for domain context related to the task:
     ```
     mcp__ruflo__memory_search(
       query: "{task.subject} {task.tags joined by space}",
       namespace: "knowledge",
       limit: 3,
       threshold: 0.4
     )
     ```
     - If results found (score >= 0.4): format as a `## Knowledge context` section with one bullet per result (`- {key}: {value preview}`). Prepend to the agent prompt.
     - If no results or ruflo unavailable: skip silently. Knowledge injection is best-effort — never blocks spawning.

   **7b. Per-task claim** (before spawning each agent):
   ```
   mcp__ruflo__claims_claim(
     issueId: "task:{task.id}",
     claimant: "agent:{swarmId}:{task.id}",
     context: "{task.subject}"
   )
   ```
   If claim fails (another agent holds it), skip this task in the batch — it may be running in a parallel session.

   - For each task in the batch, spawn a subagent via the native Agent tool — `agent_spawn`/`coordination_orchestrate` are bookkeeping-only under subscription (ADR-059; `coordination_orchestrate` self-documents "records the request but does not execute it," source-confirmed 2026-08-12) and would silently no-op the entire batch if used as the execution path:
     - `subagent_type`: from `agent_config.type` (default: `"general-purpose"`)
     - `model`: from `agent_config.model`
     - `prompt`: task subject + description + relevant context + knowledge context

   - **Non-code tasks** (research, analysis, manual):
     - Agent produces a summary/deliverable
     - Write `agent_result` to tasks.json: `{status: "completed", summary: "...", completed_at: "..."}`
     - Mark task status: completed
   - **Code tasks** (execution: code):
     - Agent reads code, composes changes, writes output to `/tmp/task-{id}-output.json`
     - Agent does NOT write to project files — compose only
     - Queue task for write-back phase
   - **Failed tasks:**
     - Write `agent_result`: `{status: "failed", error: "...", completed_at: "..."}`
     - Task stays `in_progress`. Dependents remain blocked.
     - Log error and continue with remaining tasks in batch

   **7c. Per-task release or mark-stealable** (after each task completes or fails):
   - On completion:
     ```
     mcp__ruflo__claims_release(issueId: "task:{task.id}", claimant: "agent:{swarmId}:{task.id}", reason: "completed")
     ```
   - On failure (agent timed out or errored):
     ```
     mcp__ruflo__claims_mark-stealable(issueId: "task:{task.id}", reason: "stale", context: "{error summary}")
     ```
   Skip silently if ruflo unavailable — claims are advisory, never blocking.
8. **Write-back phase** (code tasks, sequential):
   - For each completed code task:
     - Read `/tmp/task-{id}-output.json`
     - Create worktree: `git worktree add ../project-{prefix}{id} -b {prefix}{id}-{slug}`
     - Apply changes in worktree
     - Run tests (if applicable)
     - If tests pass: commit, mark completed
     - If tests fail: mark `agent_result.status: "partial"`, leave for user
     - Clean up: remove worktree
9. **Report summary** (render using task-line template icons for completed):
   ```
   Execution complete:
     ✓ 6 tasks completed
     ◐ 1 task partial (t-009: tests failed)
     ✗ 1 task failed (t-012: agent timeout)

   Milestone 'Auth System': 3/4 done
   Next: /brana:backlog execute --retry ph-002
   ```
   Icons come from active theme (✓/✅/● for completed).

### Model routing

See `system/skills/_shared/model-routing.md` for the canonical Router-as-Haiku pattern. Summary below.

Before spawning an agent for a task, compute a complexity score (0.0–1.0):

| Input | Score contribution | Max |
|-------|-------------------|-----|
| `min(word_count(description) / 100, 0.3)` | Description length | 0.3 |
| `min(len(blocked_by) * 0.1, 0.2)` | Dependency count | 0.2 |
| `0.2` if `work_type` is `implement` | Work type | 0.2 |
| `0.1` if `architecture` in tags | Architecture tag | 0.1 |
| `0.1` if effort is `L` or `XL` | Effort estimate | 0.1 |

Score → model mapping:
- **< 0.3** → haiku (simple tasks)
- **0.3–0.7** → sonnet (standard tasks)
- **> 0.7** → opus (complex tasks)

**Override:** If the task or `agent_config.model` specifies a model explicitly, that wins over the computed score.

**Logging:** Log each routing decision to the decision log as a `cost` entry (positional `<AGENT> <TYPE> <CONTENT>` — corrected t-3027, 2026-08-24): `brana decisions log backlog cost "t-NNN routed to MODEL (score: X.XX)"`

**User override tracking:** If the user explicitly requests a different model than the computed score suggests (e.g., "use opus for this"), log the override: `brana decisions log backlog cost "t-NNN override: computed=MODEL1 (score: X.XX), user chose MODEL2"`. After 10+ overrides in the same direction (e.g., user keeps upgrading haiku→sonnet), `/brana:review routing` will flag this as a threshold adjustment signal.

**Fallback:** If no task metadata is available (e.g., ad-hoc agent spawn), use the agent's default model from its frontmatter.

### Failure recovery

- `--retry` re-runs tasks with `agent_result.status` of `"failed"` or `"partial"`
- Completed tasks are skipped
- User can also fall back to manual: `/brana:backlog start <id>` on any failed task

### Schema fields (on task objects)

```json
{
  "spawn": "subagent",
  "agent_config": {"type": "general-purpose", "model": "sonnet"},
  "agent_result": null
}
```

After execution:
```json
{
  "agent_result": {
    "status": "completed",
    "summary": "Implemented JWT middleware with refresh token rotation",
    "error": null,
    "completed_at": "2026-02-18T14:30:00Z"
  }
}
```

On parent tasks, `spawn_strategy` controls child batching:
```json
{
  "type": "milestone",
  "spawn_strategy": "auto"
}
```

---

