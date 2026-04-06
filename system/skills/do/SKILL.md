---
name: do
description: "Alias for /brana:backlog start with freeform text. Routes to the best skill or creates a task. Use /brana:backlog start directly for the same behavior."
effort: low
keywords: [routing, freeform, skill-selection, auto-route, natural-language]
task_strategies: [feature, bug-fix, refactor, spike, investigation]
stream_affinity: [roadmap, tech-debt, bugs]
argument-hint: "<description of what you want to do>"
group: brana
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
  - Skill
  - mcp__ruflo__memory_search
status: stable
growth_stage: seed
---

<!-- PROCEDURE_FILE: procedures/do.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/do.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/do.md`.
