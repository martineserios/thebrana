# Dynamic Model Routing

Tasks are automatically assigned to the most appropriate model based on complexity scoring.

## How it works

Before spawning an agent for a task, the backlog skill computes a complexity score (0.0-1.0):

| Input | Score | Max |
|-------|-------|-----|
| Description word count / 100 | Length signal | 0.3 |
| Dependency count x 0.1 | Complexity signal | 0.2 |
| Stream is `roadmap` | Scope signal | 0.2 |
| Tags contain `architecture` | Depth signal | 0.1 |
| Effort is `L` or `XL` | Size signal | 0.1 |

## Thresholds

| Score | Model | Examples |
|-------|-------|---------|
| < 0.3 | haiku | Simple research, memory recall, status checks |
| 0.3-0.7 | sonnet | Code implementation, test writing, PR review |
| > 0.7 | opus | Architecture decisions, complex features, deep analysis |

## Overrides

Explicit model settings always win over computed scores:

1. **Task-level:** `agent_config.model` on the task object
2. **Agent-level:** `model:` in agent frontmatter (used when no task metadata available)
3. **User-level:** user explicitly requests a model ("use opus for this")

## Checking routing decisions

Routing decisions are logged to the decision log as `cost` entries:

```bash
# See all routing decisions
uv run python3 system/scripts/decisions.py read --type cost

# Output example:
# [2026-03-11 12:00] backlog/cost: t-348 routed to opus (score: 0.75)
# [2026-03-11 12:01] backlog/cost: t-349 routed to sonnet (score: 0.45)
```

## Calibration

The scoring function is a starting point. After collecting 30+ routing decisions, review the cost entries to check:

- Are haiku tasks actually simple? (If they fail often, raise the threshold)
- Are opus tasks actually complex? (If they're routine, lower the threshold)
- Is any input systematically misleading? (e.g., long descriptions that are actually simple)

Adjust thresholds in `system/skills/backlog/SKILL.md` based on data.
