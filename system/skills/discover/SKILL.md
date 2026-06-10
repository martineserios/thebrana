---
name: discover
description: "Runtime catalog — list all installed skills, agents, and active hooks. Use when you want to know what's available."
model: haiku
effort: low
keywords: [discover, skills, agents, hooks, catalog, list, available, inventory]
task_strategies: [investigation]
group: core
allowed-tools:
  - Bash
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/discover.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `../../procedures/discover.md` resolved against this skill's base directory (the path announced when the skill loads) — i.e. `{base-dir}/../../procedures/discover.md`. This form is valid in both the repo layout and the deployed-plugin layout.
If the path doesn't resolve, use Glob to find `**/procedures/discover.md`.
