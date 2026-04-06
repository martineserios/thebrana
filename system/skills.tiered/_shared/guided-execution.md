# Guided Execution Protocol

Multi-step skills lose track of progress during context compressions. CC Tasks survive compression. This protocol uses them as a step registry so the model can resume from where it left off.

## Step Registry

On skill entry, create CC Tasks for each major step (max 10). Use `TaskCreate` with:

- **subject**: `/brana:{skill} — {STEP_NAME}`
- **description**: What the step does + acceptance criteria
- Set `addBlockedBy` to establish execution order

As each step starts, `TaskUpdate` it to `in_progress`. When done, mark `completed`.

## Resume After Compression

After context compression, the model may lose track of progress. Resume protocol:

1. Call `TaskList` to see all step tasks
2. Find the step with status `in_progress` — that's where you were
3. If no `in_progress` step exists, find the first `pending` step whose blockers are all `completed`
4. Resume from that step using the task's description for context

## Plan Mode

For exploration-heavy steps (scanning, diagnosis, research), enter plan mode to signal read-only intent:

1. Call `EnterPlanMode` at the start of the step
2. Perform all read-only work (search, scan, analyze)
3. Call `ExitPlanMode` before any write operation

Plan mode is optional — only use it on steps explicitly marked as read-only in the skill.

## Size Gate

Skip the step registry for **Trivial** and **Small** builds (as classified by the build skill's sizing heuristics). These complete in a few minutes and don't benefit from compression resilience. The protocol adds value for **Medium** and **Large** work.

## Cleanup

When the skill completes its final step, all step tasks should be `completed`. No explicit cleanup needed — CC Tasks are session-scoped.
