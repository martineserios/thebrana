# Smart Router — Shared Strategy Detection

Reusable 2-level routing pattern for skills with multiple strategies.
Referenced by: /brana:build, /brana:research.

## The 2 Levels

### Level 1: Signal Match (~70-80% of cases)

Deterministic rules checked first. Each skill defines its own signal table.

```
ROUTER_SIGNAL(task, signals):
  for each signal in signals:
    if signal.match(task.tags, task.stream, task.description, git_state):
      return {strategy: signal.strategy, confidence: "high", level: 1}
  return null  # escalate to Level 2
```

### Level 2: Ask User (~20-30%)

When signals are ambiguous or no signal matches:

```
ROUTER_ASK(strategies):
  AskUserQuestion:
    question: "Which strategy fits this task?"
    options: [one per strategy with description]
  return {strategy: user_choice, confidence: "confirmed", level: 2}
```

> **Why not an intermediate LLM-classify step?** Claude IS the LLM — it applies its
> reasoning naturally when reading the task and signal table. A separate "classify" prompt
> adds latency without adding signal. Level 1 handles well-structured tasks; Level 2 handles
> everything else with a direct user question. (t-1711 cleanup)

## Mid-Workflow Rerouting

Gate checks at each step can trigger rerouting:
- Can't reproduce → investigate
- Root cause found → back to bug-fix
- Scope grew → reroute to feature

Rerouting is a skill-level decision. The router runs at entry; gate checks run during execution.

## Per-Skill Signal Tables

### /brana:build signals

| Signal | Strategy |
|--------|----------|
| `stream: bugs` or tag `bug` | bug-fix |
| `stream: tech-debt` or tag `refactor` | refactor |
| tag `migration` | migration |
| tag `investigation` or `spike` | investigation |
| tag `greenfield` | greenfield |
| default | feature |

### /brana:research signals

| Signal | Strategy |
|--------|----------|
| keywords: "or", "vs", "compare", "should we" | evaluate |
| keywords: "learn", "starting with", "new to" | learn |
| keywords: "broken", "why", "failing", "debug" | investigate |
| default | research |

## Logging

Log each routing decision to session state:
```json
"routing": {
  "skill": "build",
  "strategy": "bug-fix",
  "level": 1,
  "confidence": "high"
}
```
