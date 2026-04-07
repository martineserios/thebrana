---
name: docs
description: "Generate and update living documentation — tech docs, user guides, philosophy overview. Composable building block for CLOSE and other skills."
effort: medium
model: sonnet
keywords: [documentation, tech-doc, user-guide, living-docs, architecture]
task_strategies: [feature, refactor, greenfield, migration]
stream_affinity: [docs, roadmap]
argument-hint: "guide|tech|overview|all [task-id]"
group: core
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
  - Skill
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/docs.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/docs.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/docs.md`.
