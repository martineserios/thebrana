---
name: backlog
description: "Manage the backlog — plan, track, navigate phases and streams. Use when planning phases, viewing roadmaps, or restructuring work."
effort: medium
model: sonnet
keywords: [tasks, planning, roadmap, milestones, phases, tracking, priority]
task_strategies: [feature, refactor]
stream_affinity: [roadmap, tech-debt]
argument-hint: "[status|add|start|done|next|roadmap|plan|triage|tags|context|theme|sync] [args]"
group: brana
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
  - AskUserQuestion
  - Task
  - mcp__ruflo__memory_search
  - mcp__ruflo__claims_claim
  - mcp__ruflo__claims_release
  - mcp__ruflo__claims_list
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/backlog.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/backlog.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/backlog.md`.
