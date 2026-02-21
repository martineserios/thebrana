# Task Convention

## When starting work

Before branching, check `.claude/tasks.json`. If a matching task exists, use its id in the branch name and set `in_progress`. If none exists for significant work, suggest creating one.

Tasks: `{project}/.claude/tasks.json`. Archive: `.claude/tasks-archive.json`.

Fields: id, subject, description, tags, status, stream, type, parent, order, priority, effort, execution, blocked_by, branch, github_issue, created, started, completed, notes, context. Types: phase/milestone/task/subtask (ph-/ms-/t-/st-). Status: pending/in_progress/completed/cancelled. Streams: roadmap/bugs/tech-debt/docs/experiments. Execution: code/external/manual. Tags/context: null default.

**Reads**: no confirmation. **Writes**: suggest then confirm. **Planning**: discuss, propose tree, confirm, single Write.

Branch: roadmap=feat/, bugs=fix/, tech-debt=refactor/, docs=docs/. Format: `{prefix}{id}-{slug}`. Start=branch+in_progress. Done=commit+PR. External/manual: status only.

Status changes on main or task branch only. Rollup via hook. Unblocked = all blocked_by completed. Priority/effort null unless user specifies.
