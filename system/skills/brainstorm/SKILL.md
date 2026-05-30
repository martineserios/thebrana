---
name: brainstorm
description: "Interactive idea maturation — explore, research, shape raw ideas into actionable plans. Use when you have a rough idea and want to think it through."
effort: high
model: sonnet
keywords: [idea, explore, challenge, shape, opportunity, maturation]
task_strategies: [spike, feature]
stream_affinity: [roadmap, research, experiments]
argument-hint: "[idea or topic]"
group: thinking
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - Write
  - Edit
  - Agent
  - WebSearch
  - WebFetch
  - AskUserQuestion
  - Task
  - TaskList
  - Skill
  - mcp__context7__resolve-library-id
  - mcp__context7__query-docs
  - mcp__ruflo__memory_search
  - mcp__ruflo__memory_store
  - mcp__ruflo__agent_spawn
  - mcp__ruflo__hive-mind_spawn
  - mcp__ruflo__hive-mind_consensus
  - ToolSearch
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/brainstorm.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/brainstorm.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/brainstorm.md`.
