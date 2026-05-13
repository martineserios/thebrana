---
name: close
description: "End a session — extract learnings, write handoff, store patterns, detect doc drift. Use when ending a work session or when the user says done/bye/closing."
effort: high
model: sonnet
keywords: [session, handoff, debrief, learnings, errata, drift]
task_strategies: [feature, bug-fix, refactor]
stream_affinity: [roadmap, tech-debt]
argument-hint: "[focus-hint]"
group: session
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
  - Agent
  - Task
  - TaskList
  - Skill
  - mcp__ruflo__memory_store
  - mcp__ruflo__memory_search
  - mcp__ruflo__hive-mind_memory
  - mcp__ruflo__claims_release
  - mcp__ruflo__claims_list
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/close.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/close.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/close.md`.
