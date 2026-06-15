---
name: systems-thinking
description: "Map players, stocks, flows, and feedback loops to understand why a system behaves the way it does — and where leverage lives."
group: thinking
keywords: [systems-thinking, feedback-loops, stocks, flows, leverage, emergent, complexity, meadows]
task_strategies: [spike, investigation]
stream_affinity: [roadmap, research]
allowed-tools:
  - Read
  - Glob
  - Grep
  - AskUserQuestion
status: experimental
source: "Donella Meadows — Thinking in Systems (2008); Peter Senge — The Fifth Discipline (1990)"
acquired: "2026-06-15"
---
# Systems Thinking

**Map the system. Find the leverage. Stop fixing symptoms.**

Donella Meadows: "You can't navigate well in an interconnected, feedback-dominated world unless you take your eyes off short-term events and look for long-term behavior and structure." Most interventions fail because they address events, not the system producing them.

---

## When to use

- When a problem keeps recurring despite repeated fixes
- When an intervention caused an unexpected side effect
- When multiple stakeholders are working at cross-purposes
- Before designing incentive structures, org changes, or platform architecture
- When "it's complicated" — there are many interacting parts with non-obvious dependencies
- Pairs with `/brana:second-order-thinking` for consequence tracing

---

## Step 1 — Name the system and its purpose

What system are we analyzing? What is it supposed to produce?

```
AskUserQuestion: "What system are we mapping, and what is its goal or output?"
```

---

## Step 2 — Identify players and incentives

Who are the actors in this system? What does each one want?

```
Player | Goal | What they control | Key behavior
-------|------|------------------|-------------
[A]    | [X]  | [Y]              | [Z]
```

Misaligned goals are the most common source of systemic dysfunction.

---

## Step 3 — Map stocks and flows

**Stocks** = things that accumulate over time (money, users, trust, technical debt, team morale, inventory)
**Flows** = rates that change stocks (acquisition rate, churn rate, bug introduction rate, repair rate)

```
Stocks: [list]
Inflows to each: [list]
Outflows from each: [list]
```

The system's behavior comes from how stocks change over time — not from individual events.

---

## Step 4 — Identify feedback loops

**Reinforcing loops (R)** — amplify change. Growth and collapse both come from reinforcing loops.
```
R: [stock A] grows → [effect] → [stock A] grows faster
Example: Users → word-of-mouth → more Users (network effect)
```

**Balancing loops (B)** — resist change, seek equilibrium.
```
B: [stock A] grows → [negative effect] → [stock A] growth slows
Example: Technical debt grows → velocity falls → less new debt added
```

List all significant loops. Mark polarity: R or B.

---

## Step 5 — Identify delays

Where are the significant time delays between cause and effect?

Delays cause oscillation — people over-correct because they don't see the effect of their last intervention. The longer the delay, the worse the oscillation.

```
Delay: [action] → [delayed effect] (~[time horizon])
Risk: [oscillation/overshoot pattern]
```

---

## Step 6 — Find leverage points

Meadows' hierarchy (lower number = more leverage):

| Level | Leverage point | Example |
|-------|---------------|---------|
| 12 | Constants, numbers | Changing a budget by 10% |
| 11 | Size of stocks/flows | Bigger buffer inventory |
| 10 | Structure of flows | New pipeline stage |
| 9 | Delays | Faster feedback loop |
| 8 | Strength of balancing loops | Better error-correction |
| 7 | Gain of reinforcing loops | Network effect amplifier |
| 6 | Information flows | New metric surfaced to decision-maker |
| 5 | Rules | Changing an incentive structure |
| 4 | Self-organization | Enabling the system to restructure itself |
| 3 | Goals | What the system is optimizing for |
| 2 | Paradigm | The shared beliefs driving the rules |
| 1 | Transcending paradigms | Holding no paradigm as absolute truth |

Most interventions target levels 12–10 (constants, flows). High-leverage interventions target levels 9–3 (delays, information, rules, goals).

---

## Step 7 — Output

```
**Systems map of [system]**

Players: [N] — key misalignment: [X]
Key stocks: [list]
Dominant loops: [R loops] reinforcing, [B loops] balancing
Critical delays: [list]

Leverage recommendations:
1. [highest leverage point] — Level [N] — [specific intervention]
2. [second leverage point] — Level [N] — [specific intervention]

Root cause: [the structural reason the symptom recurs]
```

---

## Notes

- Counterintuitive: high-leverage points are often counterintuitive. The "obvious" intervention is usually low-leverage.
- Beware of "fixes that fail" — solutions that solve the symptom but strengthen the cause
- Information flows (Level 6) are often underutilized — making the right data visible to the right person at the right time can change behavior without any structural change
- Meadows: "The world is a complex system. Its behavior arises from structure, not from malevolent actors."
