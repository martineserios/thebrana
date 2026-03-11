# ADR-018: Dynamic Model Routing

**Date:** 2026-03-11
**Status:** accepted
**Related:** ADR-003 (agent-driven task execution), ADR-017 (decision log), t-359

## Context

Agent models are hardcoded in `system/agents/*.md` frontmatter and the backlog skill's routing table:

| Agent | Current model | Always optimal? |
|-------|:------------:|:---------------:|
| challenger | opus | Yes |
| debrief-analyst | opus | Sometimes overkill |
| scout | haiku | Sometimes too weak |
| all others | haiku | Usually fine |

The backlog skill has a static 3-row table: research→haiku, code→sonnet, architecture→opus. No task-specific routing, no cost tracking, no data on whether assignments are right.

## Decision

A complexity scoring function runs before agent spawn and overrides the default model. Decisions are logged to the decision log (ADR-017) for cost tracking.

### Scoring function (0.0–1.0)

| Input | Contribution | Max |
|-------|-------------|-----|
| `min(word_count / 100, 0.3)` | Description length | 0.3 |
| `min(dep_count * 0.1, 0.2)` | Dependency count | 0.2 |
| `0.2` if stream is `roadmap` | Stream type | 0.2 |
| `0.1` if `architecture` in tags | Architecture tag | 0.1 |
| `0.1` if effort is `L` or `XL` | Effort estimate | 0.1 |

### Thresholds

- **< 0.3** → haiku (simple)
- **0.3–0.7** → sonnet (standard)
- **> 0.7** → opus (complex)

### Override

If a task or agent config specifies a model explicitly, that wins over the computed score. Agent frontmatter models remain as defaults when no task metadata is available.

### Cost logging

Each routing decision is logged as a `cost` entry to the decision log, enabling future calibration.

## Alternatives considered

### Hard cost cap ($15/hr)
Enforced budget ceiling. Rejected: brana runs interactively with user watching. Cap would block legitimate work. Deferred to when brana runs unattended.

### Token counting
Track actual token usage per agent. Rejected: Claude Code doesn't expose per-agent token metrics. We track model tier, not actual spend. Revisit when CC exposes token data.

### Auto-calibration
Automatically adjust thresholds based on outcomes. Rejected: insufficient data at launch. Need 30+ routing decisions logged before patterns are visible. Manual calibration first.

## Consequences

- Tasks get model-appropriate compute instead of one-size-fits-all
- Cost entries in decision log enable data-driven calibration
- No hard enforcement — cost awareness without blocking
- Scoring heuristic is a starting point, not a final answer
- `blast_radius` was considered as a scoring input but removed: it's computed during /brana:build PLAN (after agent spawn), creating a circular dependency with model routing (before agent spawn)
