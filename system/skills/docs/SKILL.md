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
Read and execute `../../procedures/docs.md` resolved against this skill's base directory (the path announced when the skill loads) — i.e. `{base-dir}/../../procedures/docs.md`. This form is valid in both the repo layout and the deployed-plugin layout.
If the path doesn't resolve, use Glob to find `**/procedures/docs.md`.
