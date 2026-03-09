# Task Convention

## Before branching

1. Read `.claude/tasks.json`. State what you found.
2. Task exists → use its branch convention, set `in_progress`.
3. No task → propose one before branching.

After completing: update task to `completed` with notes.

Tasks: `{project}/.claude/tasks.json`.

Fields: id, subject, description, tags, status, stream, type, parent, order, priority, effort, execution, blocked_by, branch, github_issue, created, started, completed, notes, context, strategy, build_step. Types: phase/milestone/task/subtask (ph-/ms-/t-/st-). Status: pending/in_progress/completed/cancelled. Streams: roadmap/bugs/tech-debt/docs/experiments/research. Execution: code/external/manual. Strategy: feature/bug-fix/refactor/spike/migration/investigation/greenfield (auto-classified, user-confirmed). Build_step: specify/plan/build/close (tracks position in /brana:build loop). Tags/context: null default.

Reads: free. Writes: confirm first. Planning: propose tree, confirm.

Branch: roadmap=feat/, bugs=fix/, tech-debt=refactor/, docs=docs/, experiments=experiment/, research=research/. Format: `{prefix}{id}-{slug}`. Start=branch+in_progress+auto-classify strategy. Code tasks: `/brana:tasks start` enters `/brana:build` automatically. Done: `/brana:build` CLOSE step handles code tasks. `/brana:tasks done` is for manual/external tasks only.

## Example

```
Task t-015 (stream: roadmap) → branch: feat/t-015-jwt-auth
Task t-022 (stream: bugs)    → branch: fix/t-022-session-timeout
Task t-030 (stream: docs)    → branch: docs/t-030-api-contracts
Task t-091 (stream: research) → branch: research/t-091-graphrag-eval (most reviewed via /brana:tasks start, no branch needed)
```

Status changes on main or task branch only. Rollup via hook. Unblocked = all blocked_by completed. Priority/effort null unless user specifies.

Tasks with URLs or platform/tool names in description get brief research (via scout agent) before priority assignment. This applies when adding new tasks or during `/brana:tasks reprioritize --reresearch`.
