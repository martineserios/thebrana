# Task Convention

Tasks: `{project}/.claude/tasks.json`. Archive: `.claude/tasks-archive.json`.

Fields: id, subject, description, status, stream, type, parent, order, priority, effort, execution, blocked_by, branch, github_issue, created, started, completed, notes. Types: phase/milestone/task/subtask (prefix: ph-/ms-/t-/st-). Status: pending/in_progress/completed/cancelled. Streams: roadmap/bugs/tech-debt/docs/experiments. Execution: code/external/manual.

**Reads** (status, "what's next?"): no confirmation. **Writes**: suggest then confirm. **Planning**: discuss, propose tree, confirm, single Write.

Branch: roadmap=feat/, bugs=fix/, tech-debt=refactor/, docs=docs/. Format: `{prefix}{id}-{slug}`. Start=branch+in_progress. Done=commit+PR. External/manual: status only.

Status changes on main or task branch only. Rollup automatic via hook (all children done -> parent completes). Unblocked = all blocked_by completed. Priority/effort null unless user specifies.
