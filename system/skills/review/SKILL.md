---
name: review
description: "Business review — weekly health check, monthly close, or ad-hoc audit. Subcommands: weekly, monthly, check. Use for periodic reviews or metrics assessment."
effort: high
model: sonnet
keywords: [business, metrics, weekly, monthly, health, growth, revenue]
task_strategies: [investigation]
stream_affinity: [roadmap, research]
argument-hint: "[weekly|monthly|check]"
group: venture
allowed-tools:
  - Read
  - Write
  - Glob
  - Grep
  - Bash
  - AskUserQuestion
  - mcp__ruflo__memory_search
  - mcp__ruflo__memory_store
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/review.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/review.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/review.md`.
