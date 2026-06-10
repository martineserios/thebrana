---
name: plugin
description: "Manage Claude Code plugins — add marketplaces, install, update, remove, list. Use when installing plugins, checking status, or managing the registry."
effort: low
model: haiku
keywords: [plugin, marketplace, install, update, remove, distribution]
task_strategies: [feature, spike]
stream_affinity: [roadmap, tech-debt]
argument-hint: "[list|install|remove|update|sync] [name]"
group: brana
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Grep
  - WebFetch
  - AskUserQuestion
  - Agent
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/plugin.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `../../procedures/plugin.md` resolved against this skill's base directory (the path announced when the skill loads) — i.e. `{base-dir}/../../procedures/plugin.md`. This form is valid in both the repo layout and the deployed-plugin layout.
If the path doesn't resolve, use Glob to find `**/procedures/plugin.md`.
