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
  - mcp__ruflo__agent_spawn
  - ToolSearch
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/review.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `../../procedures/review.md` resolved against this skill's base directory (the path announced when the skill loads) — i.e. `{base-dir}/../../procedures/review.md`. This form is valid in both the repo layout and the deployed-plugin layout.
If the path doesn't resolve, use Glob to find `**/procedures/review.md`.
