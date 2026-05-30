---
name: claudemd
description: "Audit or generate a CLAUDE.md for any project. Natural companion to /brana:align — run audit after align on brownfield projects."
effort: low
model: sonnet
keywords: [CLAUDE.md, project-instructions, context, bloat, audit, generate, init]
task_strategies: [investigation, greenfield]
stream_affinity: [roadmap]
argument-hint: "[audit [path] | generate [path]]"
group: execution
allowed-tools:
  - Read
  - Glob
  - Grep
  - Write
  - Edit
  - AskUserQuestion
  - Bash
status: stable
growth_stage: evergreen
---

<!-- PROCEDURE_FILE: procedures/claudemd.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/claudemd.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/claudemd.md`.
