---
name: inversion
description: "Backward-from-failure thinking — define what would guarantee failure, then systematically avoid it."
group: thinking
keywords: [inversion, backward, failure, avoidance, munger, jacobi, contrarian, risk]
task_strategies: [spike, investigation]
stream_affinity: [roadmap, research]
allowed-tools:
  - Read
  - Glob
  - Grep
  - AskUserQuestion
status: experimental
source: "Carl Jacobi (mathematician); Charlie Munger — Poor Charlie's Almanack; mental model popularized by Farnam Street"
acquired: "2026-06-15"
---
# Inversion

**Invert the problem. Design failure actively. Then avoid everything you designed.**

Carl Jacobi: "Invert, always invert." Charlie Munger applied this to business and investing. Instead of asking "how do I succeed?", ask "how do I guarantee failure?" — then don't do that.

---

## When to use

- When you're stuck on how to achieve something
- When forward planning feels abstract or unconvincing
- As a sanity check on any plan ("what would make this fail?")
- Before a high-stakes decision
- Pairs well with `/brana:pre-mortem` (pre-mortem imagines failure; inversion actively designs it)

---

## Step 1 — State the goal

What are you trying to achieve?

```
AskUserQuestion: "What outcome do you want? One sentence."
```

---

## Step 2 — Invert the goal

Flip it completely:
- Goal: "Build a product users love"
- Inverted: "Build a product users despise and never use"

- Goal: "Ship on time"
- Inverted: "Guarantee we miss every deadline"

State the inverted goal explicitly. The more specific the inversion, the more useful the next step.

---

## Step 3 — Design failure actively

Generate everything that would guarantee the inverted goal succeeds. Use these prompts:

**To guarantee user abandonment:**
- What would make the UX maximally confusing?
- What would make support maximally unhelpful?
- What communication would maximize confusion and broken expectations?

**To guarantee technical failure:**
- What architecture decisions would ensure the system can't scale?
- What shortcuts would create the worst long-term debt?
- What dependencies would be most fragile?

**To guarantee team failure:**
- What processes would maximize burnout and conflict?
- What would maximize information silos?
- What incentives would create perverse behavior?

Generate 10–20 specific failure recipes. Don't filter.

---

## Step 4 — Recognize current failures

Honest audit: which failure recipes from Step 3 are already present in your current plan or situation?

For each match:
```
Failure recipe: [X]
Currently present as: [Y]
Severity: high / medium / low
```

---

## Step 5 — Build the avoidance strategy

For each high/medium severity match:
1. What specific change removes or reduces this failure pattern?
2. What early warning signal would indicate it's creeping back?
3. What habit or process prevents it systemically?

---

## Step 6 — Output

```
**Inversion analysis of [goal]**

Designed failure patterns: [N total]
Already present: [N high], [N medium], [N low]

Critical avoidances:
1. [pattern] → [avoidance]
2. [pattern] → [avoidance]
3. [pattern] → [avoidance]

Recommendation: [what to stop/avoid immediately]
```

---

## Notes

- The value is in generating failure patterns, not just listing obvious risks
- The exercise often reveals failures already present that were invisible from the forward direction
- Inversion and pre-mortem are complementary: inversion designs failure deliberately; pre-mortem imagines it already happened
- Munger: "It's not enough to be smart. You have to not be stupid in the ways that are obvious in retrospect."
