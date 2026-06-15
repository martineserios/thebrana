---
name: systems-thinking
description: "Map complex systems — players, incentives, stocks/flows, feedback loops, leverage points. Use when dealing with multi-stakeholder problems, platform ecosystems, org dynamics, or any situation where second/third/fourth-order effects matter more than first-order ones."
group: thinking
keywords: [systems-thinking, feedback-loops, leverage-points, incentives, stocks-flows, complexity, ecosystem, dynamics]
allowed-tools:
  - AskUserQuestion
  - Read
  - Glob
  - Grep
status: acquired
source: "https://github.com/refoundai/lenny-skills"
acquired: "2026-06-15"
---

# Systems Thinking

Help the user think in systems for complex, multi-stakeholder problems.

## When to Use

- Multi-stakeholder or multi-player problems where incentives conflict
- Platform ecosystems where actions trigger reactions
- Understanding why a "fix" keeps recreating the problem
- Organizational dynamics — why culture doesn't change despite interventions
- Finding where to intervene for maximum effect

## Core Frameworks

### 1. Map the system — players and incentives
*Seth Godin: "Strategic thinking means seeing the system — the invisible rules, culture, and interoperability that govern how things succeed or fail."*

Identify:
- **All players** — who is in this system? (users, competitors, regulators, partners, employees, adjacent systems)
- **Incentives** — what does each player optimize for?
- **Interactions** — how do players affect each other?

Don't stop at obvious players. Who is *affected* but not obviously a stakeholder? They often become players eventually.

### 2. Stocks and flows
*Will Larson: "Stocks are things that accumulate; flows are the movement from a stock to another thing."*

| Stock | Flow into it | Flow out of it |
|-------|-------------|----------------|
| User base | New signups | Churn |
| Technical debt | Features shipped without tests | Refactoring sessions |
| Team trust | Transparent communication | Missed commitments |

Model your system's key stocks and what controls the flows. This reveals: why progress feels slow (stock is large, flow is small) and why interventions often work for a while then stop.

### 3. Feedback loops
Two types:

**Reinforcing (amplifying):**  
A → B → more A → more B  
Examples: network effects, viral growth, compound interest, technical debt spiraling  
These create exponential dynamics — they're leverage when positive, traps when negative.

**Balancing (stabilizing):**  
A → B → pressure reduces A  
Examples: price elasticity, resource limits, customer service capacity  
These create ceilings and floors — important for understanding why growth plateaus.

Ask: what feedback loops are active in this system? Are they reinforcing or balancing?

### 4. Leverage points
*Donella Meadows' hierarchy (most to least powerful):*

1. **Paradigm shifts** — change the goal of the system
2. **Goals** — what the system is trying to achieve
3. **Rules** — incentives, constraints, permissions
4. **Information flows** — who gets what data when
5. **Delays** — timing of feedback affects stability
6. **Flows** — rates of change
7. **Stock sizes** — buffers and reserves

Interventions at the bottom (flows, stocks) are easier but less powerful. Interventions at the top (goals, rules, information) are harder but create system-wide change.

### 5. Second, third, fourth-order effects
*Hari Srinivasan: "Managing complex ecosystems requires thinking through effects that cascade beyond the immediate impact."*

For each proposed intervention: trace the effect chain until it stabilizes or returns to the start. Watch for:
- Effects that reverse the first-order benefit (negative feedback at 3rd order)
- New players entering once the system changes
- Delays that make causation invisible

## Steps

1. **Name the system** — what are we analyzing?
2. **Map players and incentives** — list everyone, what they optimize for
3. **Identify stocks and key flows** — what accumulates? what moves?
4. **Trace feedback loops** — reinforcing or balancing?
5. **Propose intervention** — where in the system?
6. **Find the leverage point** — at what level (Meadows hierarchy)?
7. **Trace 2nd/3rd order effects** — who reacts? what cascades?
8. **Name the systemic risk** — what would this approach miss?

## Output Format

```
Systems Analysis: [Problem/Decision]

Players and incentives:
- [Player]: optimizes for [X], affected by [Y]

Key stocks and flows:
- Stock: [what accumulates] | In: [source] | Out: [drain]

Active feedback loops:
- [Loop]: [A → B → C → A], type: [reinforcing/balancing]

Proposed intervention: [action]
Leverage level: [Meadows level]
2nd-order effects: [chain]
Systemic risk: [what this approach won't fix]

Recommendation: [action + why it's the right leverage point]
```
