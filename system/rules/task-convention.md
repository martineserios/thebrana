# Task Convention

Tasks: `{project}/.claude/tasks.json`. Archive: `.claude/tasks-archive.json`.

Fields: id, subject, description, tags, status, stream, type, parent, order, priority, effort, execution, blocked_by, branch, github_issue, created, started, completed, notes, context. Types: phase/milestone/task/subtask (prefix: ph-/ms-/t-/st-). Status: pending/in_progress/completed/cancelled. Streams: roadmap/bugs/tech-debt/docs/experiments. Execution: code/external/manual. Tags: [] default, arbitrary strings, complement streams. Context: null default, free-form string.

**Reads** (status, "what's next?"): no confirmation. **Writes**: suggest then confirm. **Planning**: discuss, propose tree, confirm, single Write.

Branch: roadmap=feat/, bugs=fix/, tech-debt=refactor/, docs=docs/. Format: `{prefix}{id}-{slug}`. Start=branch+in_progress. Done=commit+PR. External/manual: status only.

Status changes on main or task branch only. Rollup automatic via hook (all children done -> parent completes). Unblocked = all blocked_by completed. Priority/effort null unless user specifies.
