---
paths: ["system/**", ".claude/**", "docs/**"]
---

# Backlog Start Gate

When user accepts a task-continuation suggestion ("continue with t-XXX?", "start t-XXX?"),
invoke `/brana:backlog start <id>` via Skill tool BEFORE any implementation.

Exception: if user says "skip the workflow" or "just do it", proceed directly.
