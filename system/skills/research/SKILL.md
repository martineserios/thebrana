---
name: research
description: "Research a topic, doc, or creator — check sources, follow references, produce findings. Use when starting deep research on a topic or external source."
effort: high
model: sonnet
keywords: [research, topic, creator, sources, references, deep-dive, comparison, evaluate, compare, learn, investigate, debug]
task_strategies: [spike, investigation]
stream_affinity: [research]
argument-hint: "[topic|doc-number|creator:name|--refresh] [scope] [--strategy research|evaluate|learn|investigate] [--depth quick|standard|deep]"
group: learning
context: fork
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - Write
  - WebSearch
  - WebFetch
  - Task
  - mcp__ruflo__memory_search
  - mcp__ruflo__embeddings_compare
  - mcp__ruflo__memory_store
  - mcp__ruflo__agent_spawn
  - AskUserQuestion
  - ToolSearch
  - EnterPlanMode
  - TaskList
  - ExitPlanMode
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/research.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `../../procedures/research.md` resolved against this skill's base directory (the path announced when the skill loads) — i.e. `{base-dir}/../../procedures/research.md`. This form is valid in both the repo layout and the deployed-plugin layout.
If the path doesn't resolve, use Glob to find `**/procedures/research.md`.
