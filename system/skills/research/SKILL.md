---
name: research
description: "Research a topic, doc, or creator — check sources, follow references recursively, produce findings. Use when starting deep research on a topic, creator, or external source."
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
  - mcp__notebooklm__ask_question
  - mcp__notebooklm__list_notebooks
  - mcp__notebooklm__select_notebook
  - mcp__notebooklm__search_notebooks
  - mcp__notebooklm__get_health
  - mcp__ruflo__memory_search
  - mcp__ruflo__embeddings_compare
  - mcp__ruflo__memory_store
  - AskUserQuestion
  - EnterPlanMode
  - TaskList
  - ExitPlanMode
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/research.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/research.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/research.md`.
