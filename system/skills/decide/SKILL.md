---
name: decide
description: "Decision support — criteria, scenarios, patterns, recommendation."
effort: low
keywords: [decision, recommendation, what-to-do, prioritize, choose, next, options, trade-off]
task_strategies: [spike, investigation]
stream_affinity: [roadmap, research]
argument-hint: "[question or options, e.g. 'should I do A or B' / 'what to work on next']"
group: thinking
model: sonnet
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - AskUserQuestion
  - mcp__ruflo__memory_search_unified
  - mcp__ruflo__autopilot_predict
  - ToolSearch
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/decide.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `../../procedures/decide.md` resolved against this skill's base directory (the path announced when the skill loads) — i.e. `{base-dir}/../../procedures/decide.md`. This form is valid in both the repo layout and the deployed-plugin layout.
If the path doesn't resolve, use Glob to find `**/procedures/decide.md`.
