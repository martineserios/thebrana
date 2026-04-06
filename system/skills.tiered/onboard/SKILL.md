---
name: onboard
description: "Scan and diagnose a project, or scaffold a new client from scratch. Works for code and venture clients. Auto-detects project type."
effort: medium
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
Read and execute `system/procedures/onboard.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/onboard.md`.
