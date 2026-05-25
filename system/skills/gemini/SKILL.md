---
name: gemini
description: "Delegate to agy (Gemini worker) — ROUTE→ENRICH→DELEGATE→APPLY→EXTRACT→PERSIST. Use for research, boilerplate, doc drafts, batch summarization."
effort: medium
model: sonnet
keywords: [gemini, agy, delegate, research, boilerplate, batch, summarize, offload, worker, parallel]
task_strategies: [spike, investigation]
stream_affinity: [research, roadmap]
argument-hint: '"task description" | t-XXXX'
group: execution
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - ToolSearch
  - AskUserQuestion
  - mcp__brana__agy_delegate
  - mcp__brana__backlog_set
  - mcp__ruflo__memory_search
  - mcp__ruflo__memory_store
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/gemini.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/gemini.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/gemini.md`.
