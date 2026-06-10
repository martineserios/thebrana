---
name: challenge
description: "Adversarial review — Fable 5 stress-tests reasoning, Gemini checks knowledge. Use before plan or architecture decisions."
model: sonnet
effort: high
keywords: [adversarial, review, stress-test, pre-mortem, simplicity, assumptions, council]
task_strategies: [feature, refactor, migration, greenfield]
stream_affinity: [roadmap, tech-debt]
argument-hint: "[target description] [--council]"
group: learning
allowed-tools:
  - Task
  - Read
  - Glob
  - Grep
  - mcp__ruflo__hive-mind_spawn
  - mcp__ruflo__hive-mind_consensus
  - mcp__ruflo__hive-mind_shutdown
  - mcp__brana__agy_delegate
  - AskUserQuestion
  - ToolSearch
disable-model-invocation: true
context: fork
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/challenge.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `../../procedures/challenge.md` resolved against this skill's base directory (the path announced when the skill loads) — i.e. `{base-dir}/../../procedures/challenge.md`. This form is valid in both the repo layout and the deployed-plugin layout.
If the path doesn't resolve, use Glob to find `**/procedures/challenge.md`.
