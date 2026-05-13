---
name: memory
description: "Knowledge system operations — recall patterns, cross-pollinate across clients, audit docs for contradictions. Subcommands: recall, pollinate, review, review --audit. Use for pattern queries, cross-client transfer, or knowledge audits."
effort: medium
keywords: [knowledge, recall, patterns, cross-pollinate, audit, memory]
task_strategies: [investigation, spike]
stream_affinity: [research, tech-debt]
argument-hint: "[recall|pollinate|review|review --audit] [query]"
group: learning
allowed-tools:
  - Agent
  - AskUserQuestion
  - Bash
  - Glob
  - Grep
  - Read
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/memory.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/memory.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/memory.md`.
