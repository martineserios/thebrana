---
name: challenge
description: "Adversarial review — Opus stress-tests reasoning, Gemini stress-tests documented knowledge. Add --council for 4-perspective debate. Use when a plan, decision, or architecture needs stress-testing."
effort: max
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
  - mcp__notebooklm__ask_question
  - mcp__notebooklm__search_notebooks
  - mcp__notebooklm__get_health
  - AskUserQuestion
disable-model-invocation: true
context: fork
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/challenge.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/challenge.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/challenge.md`.
