# Model Routing — Router-as-Haiku Pattern

Cost-aware agent spawning. Referenced by: /brana:build, /brana:backlog execute.

## Pattern

The Router-as-Haiku pattern separates two concerns:
1. **Classification (Haiku)** — compute the complexity score and pick a model tier. Fast, cheap, deterministic.
2. **Execution (Haiku/Sonnet/Fable)** — do the actual work at the right tier.

Never spawn a Sonnet/Fable agent when a Haiku agent can do the job. The cost difference is 10-80× depending on the model pair.

## Complexity Score (0.0–1.0)

| Input | Contribution | Cap |
|-------|-------------|-----|
| `min(word_count(description) / 100, 0.3)` | Description length | 0.3 |
| `min(len(blocked_by) × 0.1, 0.2)` | Dependency depth | 0.2 |
| `0.2` if `work_type` is `implement` | Work type | 0.2 |
| `0.1` if tag `architecture` present | Architecture scope | 0.1 |
| `0.1` if effort is `L` or `XL` | Effort estimate | 0.1 |

## Score → Model

| Score | Model | Use for |
|-------|-------|---------|
| < 0.3 | haiku | Simple tasks: chores, docs updates, small fixes, S effort |
| 0.3–0.7 | sonnet | Standard tasks: features, M effort, most implementation |
| > 0.7 | fable | Complex tasks: architecture, L/XL effort, cross-cutting changes |

## Override Precedence

1. Explicit `agent_config.model` field on the task — highest priority
2. User-requested model (log as override)
3. Computed score — default

## Applying the Pattern

When delegating a subtask to an agent:

```
score = complexity_score(task)
model = score < 0.3 ? "haiku" : score < 0.7 ? "sonnet" : "fable"

# Override check
if task.agent_config?.model: model = task.agent_config.model

Agent(subagent_type: "claude", model: model, prompt: "{subtask description + TDD checklist}")
```

(ruflo's `agent_spawn` MCP tool is bookkeeping-only under subscription, ADR-059 — it registers metadata but never runs the subtask, so the native Agent tool is the dispatch path, not a fallback.)

## Logging

Log every routing decision (positional `<AGENT> <TYPE> <CONTENT>` — corrected t-3027, 2026-08-24, drifted `--agent`/`--entry-type`/`--content` flags never existed on the CLI):
```
brana decisions log build cost "t-NNN routed to {model} (score: {score:.2f})"
```

Log overrides separately:
```
brana decisions log build cost "t-NNN override: computed={model1} (score: {score:.2f}), using {model2}"
```

After 10+ overrides in one direction, `/brana:review routing` flags it as a threshold adjustment signal.

## Fallback

If no task metadata is available (ad-hoc delegation, no task ID): use the skill's own frontmatter model as default.
