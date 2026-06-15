---
name: second-order-thinking
description: "Chain-reaction mapping — trace consequences beyond the obvious first effect to reveal hidden risks and opportunities."
group: thinking
keywords: [second-order, consequences, chain-reaction, effects, howard-marks, systems, downstream]
task_strategies: [spike, investigation]
stream_affinity: [roadmap, research]
allowed-tools:
  - Read
  - Glob
  - Grep
  - AskUserQuestion
status: experimental
source: "Howard Marks — The Most Important Thing (2011); Garrett Hardin — Filters Against Folly (1986)"
acquired: "2026-06-15"
---
# Second-Order Thinking

**And then what? And then what after that?**

Howard Marks: "First-level thinkers look for simple formulas and easy answers. Second-level thinking is deep, complex, and convoluted." Most decisions fail not from their direct effects but from their cascades.

---

## When to use

- Before implementing a change that affects many people or systems
- When evaluating a decision that seems obviously good (a sign first-level thinking is in play)
- When something feels like an improvement but you sense a catch
- When designing incentive structures, policies, or architecture
- Pairs with `/brana:systems-thinking` for complex adaptive systems

---

## Step 1 — State the action or decision

What change or decision are we analyzing?

```
AskUserQuestion: "What action or decision are we tracing consequences for?"
```

---

## Step 2 — Map first-order effects

What are the direct, immediate consequences? These are what most people think about.

Format:
```
Action → [direct effect 1]
Action → [direct effect 2]
Action → [direct effect 3]
```

---

## Step 3 — Map second-order effects

For each first-order effect: "And then what?"

```
[direct effect 1] → [consequence 1a]
[direct effect 1] → [consequence 1b]
[direct effect 2] → [consequence 2a]
```

Focus these lenses:

| Lens | Question |
|------|----------|
| **Behavioral** | How will people adapt their behavior in response? |
| **Competitive** | How will competitors or opponents respond? |
| **Resource** | What gets consumed, depleted, or crowded out? |
| **Systemic** | What feedback loops does this trigger? |
| **Temporal** | What looks good short-term but bad long-term (or vice versa)? |

---

## Step 4 — Map third-order effects (optional, high-stakes)

For the most significant second-order effects: "And then what after that?"

Stop at third order unless the chain is still producing surprises. Most useful insight lives in 2nd order.

---

## Step 5 — Identify hidden risks and opportunities

From the full map:

**Hidden risks** — second/third-order effects that undermine the goal or create new problems:
```
Risk: [effect chain] → threatens [X]
Severity: high / medium / low
```

**Hidden opportunities** — second/third-order effects that could be amplified:
```
Opportunity: [effect chain] → enables [X]
How to capture: [specific action]
```

---

## Step 6 — Output

```
**Second-order analysis of [action/decision]**

1st order: [summary of direct effects]

Critical 2nd-order surprises:
- [effect] → [consequence] [risk/opportunity]
- [effect] → [consequence] [risk/opportunity]

Decision impact:
→ Proceed / Modify / Avoid
Modification: [if needed]
```

---

## Notes

- The goal is not to paralyze with consequences but to anticipate the most important surprises
- "Obviously good" decisions most need this analysis — consensus on first-level is a warning sign
- Hardin's filter: run the analysis through literacy (what does it say?), numeracy (at what scale?), and ecolacy (and then what?) lenses
- Time horizon matters: explicitly distinguish short-term vs long-term effects
- Pair with `/brana:pre-mortem` after this analysis to stress-test the full consequence map
