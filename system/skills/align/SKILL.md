---
name: align
description: "Actively align a project with brana practices — assess gaps, plan fixes, implement structure, verify. Works for code, venture, and brainstorm/research repos. Auto-detects type. Use when setting up a new project or realigning an existing one."
effort: medium
model: sonnet
keywords: [alignment, structure, conventions, gaps, brana-practices]
task_strategies: [refactor, greenfield]
stream_affinity: [roadmap, tech-debt]
argument-hint: "[project-path]"
group: execution
depends_on:
  - onboard
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
  - Task
  - EnterPlanMode
  - ExitPlanMode
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/align.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/align.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/align.md`.
