---
description: M+ effort plans must include DDD/TDD/SDD/Docs tasks as blockers. Missing discipline = tech debt.
globs: ["docs/**/*.md", "system/procedures/*.md"]
alwaysApply: false
---

# M+ Discipline Enforcement

Any plan, backlog, or build output for efforts M or larger MUST include all four disciplines:

- **DDD:** At least one ADR task, blocking all implementation tasks in its decision area.
- **TDD:** At least one test task per implementation task, appearing before the impl task in the backlog order.
- **SDD:** At least one spec update task per feature, blocked_by its impl task.
- **Docs:** At least one user guide or /brana:docs task per user-facing feature.

If any discipline is missing when you produce a plan: surface it as a WARNING. If the user accepts the override path, file a P2 tech-debt task before proceeding.

This rule was created to fix a gap identified in the 2026-04-18 lexia brainstorm session where all four disciplines were absent from a 12-day build plan (t-1308).
