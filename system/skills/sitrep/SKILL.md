---
name: sitrep
description: "Situational awareness — where am I, what was I doing, what's next. Context recovery after compression, confusion, or mid-session reorientation."
effort: low
keywords: [status, context, recovery, orientation, compression, where-am-i]
task_strategies: [investigation]
stream_affinity: [roadmap, tech-debt]
argument-hint: "[--tag <tag>] [--stream <stream>] [--kind <kind>] [--priority <p>]"
group: core
model: haiku
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - Task
  - AskUserQuestion
  - mcp__ruflo__hooks_intelligence_pattern-search
  - mcp__ruflo__hive-mind_memory
  - mcp__ruflo__memory_search_unified
  - mcp__ruflo__autopilot_predict
  - mcp__ruflo__claims_board
  - mcp__brana__session_history
  - ToolSearch
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/sitrep.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/sitrep.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/sitrep.md`.
