---
name: onboard
description: "Scan and diagnose a project, or scaffold a new client from scratch. Works for code and venture clients. Auto-detects project type."
effort: medium
model: haiku
keywords: [scan, diagnose, project, structure, tech-stack, gaps, scaffold, new-client]
task_strategies: [investigation, greenfield]
stream_affinity: [roadmap]
argument-hint: "[new [slug] | project-path]"
group: execution
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - Write
  - Edit
  - AskUserQuestion
  - Task
  - TaskList
  - Skill
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/onboard.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `../../procedures/onboard.md` resolved against this skill's base directory (the path announced when the skill loads) — i.e. `{base-dir}/../../procedures/onboard.md`. This form is valid in both the repo layout and the deployed-plugin layout.
If the path doesn't resolve, use Glob to find `**/procedures/onboard.md`.
