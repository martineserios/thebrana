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
# Do — Alias for backlog start

`/brana:do` is an alias for `/brana:backlog start` with freeform text input.

## Usage

`/brana:do <description>`

## How it works

Invoke `/brana:backlog start` with the arguments treated as freeform text (step 1a of the start procedure):

```
Skill(skill="brana:backlog", args="start $ARGUMENTS")
```

All routing, skill matching, task creation, and batch detection logic lives in `/brana:backlog start`. See `system/skills/backlog/phases/start.md` § `/brana:backlog start` → step 1a.
