---
name: do
description: "Route freeform text to the best skill — alias for backlog start with natural language input. Semantic skill matching via ruflo memory."
effort: low
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

# Do — Freeform Skill Router

Alias for `brana backlog start` with freeform text input. Instead of specifying a task ID,
describe what you want to do in natural language and the system routes to the best skill.

## Usage

`/brana:do <description>`

Examples:
- `/brana:do fix the authentication race condition`
- `/brana:do set up monitoring for the API`
- `/brana:do refactor the session handling module`

## How it works

1. Parse `$ARGUMENTS` as freeform text
2. Read `skill_routing` thresholds from `~/.claude/tasks-config.json` (same config as backlog start)
3. Search for matching skills via ruflo:
   ```
   mcp__ruflo__memory_search(
     query: "$ARGUMENTS",
     namespace: "skills",
     limit: 5,
     threshold: 0.3
   )
   ```
4. If MCP unavailable, fall back to CLI: `brana skills suggest --query "$ARGUMENTS"`
5. Present results using the same threshold logic as `/brana:backlog start` step 5:
   - Above suggest_threshold (0.5): suggest via AskUserQuestion
   - Between thresholds (0.3–0.5): mention inline
   - Below mention_threshold (0.3): offer marketplace search
6. If user selects a skill, invoke it: `Skill(skill="brana:{name}", args="$ARGUMENTS")`
7. If user selects "Create task first", invoke: `Skill(skill="brana:backlog", args="start \"$ARGUMENTS\"")`

## Difference from backlog start

| | `backlog start <id>` | `/brana:do <text>` |
|--|---------------------|-------------------|
| Input | Task ID (structured metadata) | Freeform text |
| Query source | Task subject + tags + strategy | Raw user text |
| Task creation | Task exists | Optional — user can create or skip |
| Branch | Created from task slug | Not created (unless user creates task) |

## Rules

- Never auto-invoke a skill without user confirmation
- If no `$ARGUMENTS` provided, ask: "What do you want to do?"
- Keep it fast — one MCP call, one AskUserQuestion, done
