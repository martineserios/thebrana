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
  - mcp__ruflo__autopilot_learn
  - ToolSearch
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/fix.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `../../procedures/fix.md` resolved against this skill's base directory (the path announced when the skill loads) — i.e. `{base-dir}/../../procedures/fix.md`. This form is valid in both the repo layout and the deployed-plugin layout.
If the path doesn't resolve, use Glob to find `**/procedures/fix.md`.
