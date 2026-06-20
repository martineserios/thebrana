# hive-mind workflow

The real version of what ruflo's `hive-mind_*` / `swarm_*` / `coordination_consensus` MCP tools only mock. Runs on your Claude **subscription** via the native `Workflow` tool — no API key, no ruflo daemon.

> Why this exists: ruflo's agentic MCP surface is coordination metadata gated behind a paid API key — under subscription-only it spawns records and returns fabricated metrics, but nothing thinks. See `field-note_ruflo-agentic-layer-subscription-theater`. Native subagents do the thing ruflo only role-plays.

## Shape

```
Convene  →  N workers answer the question, each locked to a distinct lens (parallel)
Verify   →  each answer is adversarially stress-tested by a skeptic (no barrier — verifies as each lands)
Synthesize → survivors merged into one decisive, disagreement-aware answer
```

This is genuine "collective intelligence + consensus": independent perspectives, real adversarial verification (not a 1-node self-vote), and a synthesis that surfaces disagreement instead of papering over it.

## Run it

```js
// By name — works in any session AFTER the one where the file was created
// (the registry is built at session start, so a freshly-created file resolves next session).
Workflow({ name: "hive-mind", args: { question: "should we adopt X or Y?" } })

// By path — works immediately, including the session you created/edited it in.
Workflow({ scriptPath: ".claude/workflows/hive-mind.js", args: { question: "..." } })
```

### args

| key | required | default | meaning |
|-----|----------|---------|---------|
| `question` | yes | — | what the hive answers (a bare string `args` also works) |
| `workers` | no | `3` | fan-out count, capped at available lenses |
| `lenses` | no | diverse general set | custom perspectives, e.g. `["cost", "security", "DX"]` |
| `model` | no | inherit | model alias for every agent (`haiku` for cheap smoke tests) |

Default lenses: first-principles, evidence, skeptic, practitioner, systems.

### returns

```js
{ question, workers, survived, answer /* synthesized */, detail: [{ lens, held_up, confidence, problems }] }
```

## When to use it vs. plain Task fan-out

- **Plain Task fan-out** (multiple `Agent` calls in one message): quick parallel investigation, no verification loop. Cheapest.
- **hive-mind**: when the answer matters enough to want independent perspectives *and* adversarial verification *and* synthesis — decisions, ambiguous questions, "is this actually right?".
- **deep-research** (built-in): when the bottleneck is sourcing/citing external info rather than reasoning over a known space.

## Cost

`workers × 2` agents (worker + verifier) plus one synthesizer. Default 3 workers ≈ 7 agents. Use `model: "haiku"` and `workers: 2` for smoke tests.
