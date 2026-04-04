# Guided Execution Protocol

Multi-step skills lose track of progress during context compressions. CC Tasks survive compression. This protocol uses them as a step registry so the model can resume from where it left off.

## Three-Tool Model

Skills use up to three Claude Code native tools depending on workflow complexity:

| Tool | Purpose | When to use |
|------|---------|-------------|
| **Plan Mode** (`EnterPlanMode`/`ExitPlanMode`) | Read-only analysis, structured plan output, approval gate | Steps that scan, research, or analyze before writing |
| **Tasks API** (`TaskCreate`/`TaskUpdate`/`TaskList`) | Persistent step tracking with dependencies, compression resilience | Medium/Large multi-step workflows (5+ steps, cross-session risk) |
| **TodoWrite** | Simple session progress checklist shown in status bar | Lightweight workflows (3-4 steps, single-session, no dependencies) |

### Decision guide

```
Is the skill 5+ steps with compression risk?
  YES → Tasks API (step registry) + Plan Mode (for read-only phases)
  NO  → Is it 3-4 steps, single-session?
          YES → TodoWrite (simple checklist)
          NO  → No tracking tool needed
```

### Plan Mode + Tasks API together

For skills that use both, the pattern is:

```
EnterPlanMode           ← read-only analysis phase
  Step A (read-only)    ← tracked by Tasks API as in_progress
  Step B (read-only)    ← tracked by Tasks API as in_progress
ExitPlanMode            ← before first write or interactive step
  Step C (interactive)  ← AskUserQuestion for approval
  Step D (write)        ← execute, write files, commit
```

Plan mode governs what Claude CAN do (read-only vs read-write).
Tasks API governs what Claude HAS done (progress tracking).
They are orthogonal — use both when the workflow benefits.

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

1. Call `EnterPlanMode` at the start of the read-only phase
2. Perform all read-only work (search, scan, analyze)
3. Call `ExitPlanMode` before any write operation or interactive step (AskUserQuestion)

Plan mode is optional — only use it on steps explicitly marked as read-only in the skill.

**Skills currently using plan mode:**

| Skill | Plan mode phases | Exit before |
|-------|-----------------|-------------|
| `/brana:build` | SPECIFY, DECOMPOSE | APPROVE |
| `/brana:research` | INTERNAL-SEARCH, WIDE-SCAN, TRIAGE | DEEP-DIVE |
| `/brana:reconcile` | SCAN-SPECS, SCAN-IMPL, DIFF | PRESENT |
| `/brana:close` | GATE, GATHER, EXTRACT | ERRATA |
| `/brana:onboard` | DETECT, SCAN, RECALL, GAPS | REPORT |
| `/brana:align` | DISCOVER, ASSESS | PLAN |
| `/brana:venture-phase` | ORIENT, RECALL | PLAN |
| `/brana:backlog plan` | DETECT, READ, MILESTONES, TASKS, DEPS | PROPOSE |

## TodoWrite (Lightweight Alternative)

For skills with 3-4 steps that complete in a single session, use TodoWrite instead of the Tasks API. TodoWrite provides user-visible progress without persistent storage or dependency tracking overhead.

**Skills using TodoWrite instead of Tasks API:**

| Skill | Steps |
|-------|-------|
| `/brana:pipeline` | DETECT, LOAD, ACTION, REPORT |
| `/brana:respondio-prompts` | ORIENT, AUDIT, WRITE, VALIDATE |

TodoWrite skills do NOT need a resume-after-compression protocol — if context compresses during a 4-step flow, the overhead of resuming exceeds just re-running.

## Size Gate

Skip the step registry for **Trivial** and **Small** builds (as classified by the build skill's sizing heuristics). These complete in a few minutes and don't benefit from compression resilience. The protocol adds value for **Medium** and **Large** work.

## Cleanup

When the skill completes its final step, all step tasks should be `completed`. No explicit cleanup needed — CC Tasks are session-scoped.
