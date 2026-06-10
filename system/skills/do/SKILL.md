---
name: do
description: "Alias for /brana:backlog start with freeform text. Routes to the best skill or creates a task. Use /brana:backlog start directly for the same behavior."
effort: low
model: haiku
keywords: [routing, freeform, skill-selection, auto-route, natural-language]
task_strategies: [feature, bug-fix, refactor, spike, investigation]
stream_affinity: [roadmap, tech-debt, bugs]
argument-hint: "<description of what you want to do>"
group: brana
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
  - Skill
  - mcp__ruflo__memory_search
status: stable
growth_stage: seed
---

<!-- PROCEDURE_FILE: procedures/do.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `../../procedures/do.md` resolved against this skill's base directory (the path announced when the skill loads) — i.e. `{base-dir}/../../procedures/do.md`. This form is valid in both the repo layout and the deployed-plugin layout.
If the path doesn't resolve, use Glob to find `**/procedures/do.md`.
