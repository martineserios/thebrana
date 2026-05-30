---
name: reconcile
description: "Unified maintenance — detect drift, run security checks, cascade spec propagation, knowledge hygiene. Scoped via --scope flag. Default: consistency."
effort: high
model: sonnet
keywords: [drift, specs, implementation, sync, mismatch, system, security, audit, propagation, maintain, knowledge]
task_strategies: [refactor, investigation]
stream_affinity: [tech-debt, docs]
argument-hint: "[--scope consistency|security|propagation|knowledge|all]"
group: brana
allowed-tools:
  - AskUserQuestion
  - Bash
  - Edit
  - EnterPlanMode
  - ExitPlanMode
  - Glob
  - Grep
  - Read
  - Skill
  - Task
  - TaskList
  - Write
  - mcp__ruflo__memory_search
  - mcp__ruflo__memory_delete
  - mcp__ruflo__memory_store
  - ToolSearch
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/reconcile.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/reconcile.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/reconcile.md`.
