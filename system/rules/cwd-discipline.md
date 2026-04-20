---
paths: ["system/**", ".claude/**", "docs/**"]
alwaysApply: true
---

# CWD Discipline

Always start Claude Code from the project root (e.g., ~/enter_thebrana/thebrana/),
never from a parent workspace directory like ~/enter_thebrana/.

Write permission blast radius = CWD + all subdirectories. Starting from a parent
directory expands write access to the entire portfolio.
