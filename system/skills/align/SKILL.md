---
name: align
description: "Align a project to brana practices — assess gaps, plan, implement, verify. Auto-detects type. Use when setting up a new project or realigning an existing one."
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
Read and execute `../../procedures/align.md` resolved against this skill's base directory (the path announced when the skill loads) — i.e. `{base-dir}/../../procedures/align.md`. This form is valid in both the repo layout and the deployed-plugin layout.
If the path doesn't resolve, use Glob to find `**/procedures/align.md`.
