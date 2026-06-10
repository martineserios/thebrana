---
name: acquire-skills
description: "Find and install skills for project tech gaps. Use when entering a project with unfamiliar tech or when no local skill matches a task context."
effort: low
model: haiku
keywords: [skills, marketplace, install, gap, discovery, external]
task_strategies: [feature, spike]
stream_affinity: [roadmap, tech-debt]
group: brana
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Grep
  - WebSearch
  - WebFetch
  - AskUserQuestion
  - Agent
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/acquire-skills.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `../../procedures/acquire-skills.md` resolved against this skill's base directory (the path announced when the skill loads) — i.e. `{base-dir}/../../procedures/acquire-skills.md`. This form is valid in both the repo layout and the deployed-plugin layout.
If the path doesn't resolve, use Glob to find `**/procedures/acquire-skills.md`.
