---
name: fix
description: "Structured bug fix — reproduce (failing test), diagnose, fix (minimal change), verify, commit. Enforces test-first. Use when a bug needs a methodical fix."
effort: medium
model: sonnet
keywords: [bug, fix, broken, error, crash, failing, regression, debug, diagnose, reproduce, root-cause]
task_strategies: [bug-fix]
stream_affinity: [bugs, tech-debt]
argument-hint: "[task-id or description of the bug]"
group: execution
depends_on:
  - backlog
allowed-tools:
  - AskUserQuestion
  - Bash
  - Edit
  - Glob
  - Grep
  - Read
  - Write
  - Agent
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/fix.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/fix.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/fix.md`.
