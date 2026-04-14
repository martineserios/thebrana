---
name: retrospective
description: Store a learning in the memory taxonomy — classify by type (Rule/Pattern/Knowledge/Decision/Reference), then route to canonical destination (patterns.md, knowledge-staging.md, ADR stub, portfolio.md). Use after notable discoveries, unexpected issues, successful workarounds, or when a reusable pattern emerges.
effort: low
keywords: [learning, pattern, discovery, workaround, knowledge]
task_strategies: [feature, bug-fix, refactor, spike]
stream_affinity: [roadmap, tech-debt, research]
argument-hint: "[learning text]"
group: learning
model: sonnet
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/retrospective.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/retrospective.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/retrospective.md`.
