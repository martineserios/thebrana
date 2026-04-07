---
name: plugin
description: "Manage Claude Code plugins — add marketplaces, install, update, remove, list plugins. Use when installing new plugins, checking plugin status, or managing the plugin registry."
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
Read and execute `system/procedures/plugin.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/plugin.md`.
