---
name: retrospective
description: Store a learning — classify type, route to canonical destination. Use after discoveries, unexpected issues, workarounds, or when a reusable pattern emerges.
effort: low
keywords: [learning, pattern, discovery, workaround, knowledge]
task_strategies: [feature, bug-fix, refactor, spike]
stream_affinity: [roadmap, tech-debt, research]
argument-hint: "[learning text]"
group: learning
model: haiku
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
  - mcp__ruflo__memory_search
  - ToolSearch
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/retrospective.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/retrospective.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/retrospective.md`.
