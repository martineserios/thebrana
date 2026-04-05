# Smart Router — Shared Strategy Detection

Reusable 3-level routing pattern for skills with multiple strategies.
Referenced by: /brana:build, /brana:research.

## The 3 Levels

### Level 1: Signal Match (~60-70% of cases)

Deterministic rules checked first. Each skill defines its own signal table.

```
ROUTER_SIGNAL(task, signals):
  for each signal in signals:
    if signal.match(task.tags, task.stream, task.description, git_state):
      return {strategy: signal.strategy, confidence: "high", level: 1}
  return null  # escalate to Level 2
```

### Level 2: LLM Classify (~25-30%)

When signals are ambiguous, use a brief classification prompt:

```
ROUTER_LLM(task, strategies):
  prompt = """
  Task: {task.subject}
  Description: {task.description}
  Tags: {task.tags}
  Context: {task.context}
  
  Classify into ONE of: {strategies | join(", ")}
  
  Respond with: strategy_name (confidence: high/medium/low)
  """
  result = LLM(prompt)
  if result.confidence in ["high", "medium"]:
    return {strategy: result.strategy, confidence: result.confidence, level: 2}
  return null  # escalate to Level 3
```

### Level 3: Ask User (~5-10%)

When LLM confidence is low:

```
ROUTER_ASK(strategies):
  AskUserQuestion:
    question: "Which strategy fits this task?"
    options: [one per strategy with description]
  return {strategy: user_choice, confidence: "confirmed", level: 3}
```

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
