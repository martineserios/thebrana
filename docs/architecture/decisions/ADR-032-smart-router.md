---
depends_on:
  - docs/architecture/features/operating-model.md
  - docs/architecture/decisions/ADR-029-six-job-taxonomy.md
  - docs/architecture/decisions/ADR-027-auto-learning-loop.md
status: accepted
---

# ADR-032: Smart Router (Shared Strategy Detection)

**Date:** 2026-04-04
**Status:** accepted
**Tasks:** t-901
**Source:** Operating model §5

## Context

Both `/brana:build` and `/brana:research` need to detect which strategy to use. Today, each skill has its own ad-hoc routing logic: /build checks tags and git state, /research checks task description keywords. This duplicates effort and produces inconsistent behavior.

The operating model identifies a shared 3-level routing pattern that works across skills:

1. Signal match (deterministic) — covers ~60-70%
2. LLM classify (when signals are ambiguous) — covers ~25-30%
3. Ask user (when LLM is uncertain) — covers ~5-10%

## Decision

Implement a shared routing function, parameterized per skill's strategy set. All routing logic lives in skill markdown — no code.

### 3-Level Escalation

| Level | Mechanism | When | Example |
|-------|-----------|------|---------|
| **1. Signal** | Tags, stream, keywords, git state, file patterns | Clear signals present | `tags: [bug]` → bug-fix strategy |
| **2. LLM** | Prompt template classifies from task context | Signals ambiguous | "Refactor auth module" → refactor or feature? |
| **3. Ask** | AskUserQuestion with strategy options | LLM confidence low | "Is this a refactor or a new feature?" |

### Per-Skill Strategy Sets

| Skill | Strategies | Signal examples |
|-------|-----------|----------------|
| `/brana:build` | feature, bug-fix, refactor, migration, investigation, greenfield | `stream: bugs` → bug-fix; `tags: [spike]` → investigation |
| `/brana:research` | research, evaluate, learn, investigate | "What is X?" → research; "X or Y?" → evaluate; "Why broken?" → investigate |

### Shared Function Structure

```
ROUTER(task, skill_strategies):
  1. Check Level 1 signals (per-skill signal table)
     → if match: return strategy + confidence: high
  2. Build LLM prompt: task description + context + strategy definitions
     → if LLM confidence > threshold: return strategy + confidence: medium
  3. Present AskUserQuestion with strategy options
     → return user choice + confidence: confirmed
```

The function is defined once in a shared section of each skill's markdown. Each skill provides its own signal table and strategy definitions.

### Mid-Workflow Rerouting

Gate checks at each build step can trigger rerouting:

- Can't reproduce bug → reroute to investigate
- Root cause found during investigation → reroute back to bug-fix
- Scope grew during feature → reroute to migration
- Spike yielded clear architecture → reroute to feature

Rerouting is a skill-level decision, not a router decision. The router runs at entry; gate checks run during execution.

### Self-Learning (Deferred)

The operating model proposes logging routing decisions to ruflo and auto-promoting consistent reroutes to Level 1 signal rules. This is deferred to Phase D+ because:

1. We need reroute data to justify the infrastructure
2. Levels 1+2 cover ~90% of cases
3. Self-learning adds complexity before we know the patterns

Phase D5 implements levels 1+2 only. Self-learning activates when reroute data (10+ consistent patterns) justifies it.

## Consequences

- `/brana:build` and `/brana:research` share a common routing pattern
- New strategy-based skills adopt the same 3-level pattern
- AskUserQuestion usage drops (Level 1+2 handle ~90%)
- Routing decisions are transparent (logged with confidence level)
- No code — all logic in skill markdown prompts
- Self-learning infrastructure deferred until data-justified
