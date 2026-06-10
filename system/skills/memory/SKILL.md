---
name: memory
description: "Knowledge system ops — recall, pollinate, audit docs. Subcommands: recall, pollinate, review. Use for pattern queries, cross-client transfer, or audits."
model: haiku
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
Read and execute `../../procedures/memory.md` resolved against this skill's base directory (the path announced when the skill loads) — i.e. `{base-dir}/../../procedures/memory.md`. This form is valid in both the repo layout and the deployed-plugin layout.
If the path doesn't resolve, use Glob to find `**/procedures/memory.md`.
