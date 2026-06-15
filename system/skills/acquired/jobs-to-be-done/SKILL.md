---
name: jobs-to-be-done
description: "Understand what customers are actually hiring a product to do — functional, emotional, and social dimensions — to design solutions that win."
group: thinking
keywords: [jtbd, jobs-to-be-done, christensen, ulwick, customer, need, outcome, innovation, product]
task_strategies: [spike, investigation]
stream_affinity: [roadmap, research]
allowed-tools:
  - Read
  - Glob
  - Grep
  - AskUserQuestion
status: experimental
source: "Clayton Christensen — The Innovator's Solution (2003); Tony Ulwick — Jobs to be Done (2016); Bob Moesta"
acquired: "2026-06-15"
---
# Jobs to Be Done

**What job is the customer hiring your product to do?**

Christensen: people don't buy products — they hire them to make progress in their life. The job is the unit of analysis, not the customer segment or the product feature. Understanding the job predicts what will win.

---

## When to use

- Before designing a new feature or product
- When users are churning or not adopting an existing feature
- When the problem feels like "why don't they use it the way we designed it?"
- When evaluating product-market fit
- When prioritizing among competing features
- Pairs with `/brana:first-principles` for stripping assumptions from the job definition

---

## Step 1 — Identify the job

What progress is the customer trying to make?

```
AskUserQuestion: "What product, feature, or behavior are we analyzing through JTBD?"
```

The job statement format:
```
When [situation], I want to [motivation], so I can [expected outcome].
```

Example: "When I wake up late and need to look professional quickly, I want to find an outfit that works, so I can get out the door without anxiety."

The trigger situation matters as much as the goal.

---

## Step 2 — Map the three job dimensions

Every job has three dimensions. All three must be addressed for a product to win.

| Dimension | Definition | Example |
|-----------|-----------|---------|
| **Functional** | The practical task to be accomplished | "Transfer files between devices" |
| **Emotional** | How the customer wants to feel | "Feel in control and not anxious" |
| **Social** | How the customer wants to be perceived by others | "Look like someone who's organized and professional" |

Map all three. Products that only solve the functional dimension often lose to competitors that also solve emotional/social.

---

## Step 3 — Map the job lifecycle

Jobs have a lifecycle with distinct phases, each with its own set of desired outcomes:

| Phase | What the customer does |
|-------|----------------------|
| **Define** | Determine goals and plans |
| **Locate** | Gather inputs needed |
| **Prepare** | Set up environment |
| **Confirm** | Verify readiness |
| **Execute** | Perform the core job |
| **Monitor** | Check progress |
| **Modify** | Make adjustments |
| **Conclude** | Finish and wrap up |

For the job you're analyzing: which phases are painful or broken right now?

---

## Step 4 — Identify desired outcomes (Ulwick's outcome-driven innovation)

Desired outcomes are the metrics customers use to evaluate success. They follow the format:
```
[Direction] + [metric] + [object] + [context/clarifier]
```

Example: "Minimize the time it takes to find the right file when working across multiple devices"

Generate 10–20 desired outcomes across the job lifecycle. Then rate each:
- **Importance**: How important is this to the customer? (1–10)
- **Satisfaction**: How well is this currently addressed? (1–10)

**Opportunity score** = Importance + max(0, Importance − Satisfaction)

High importance + low satisfaction = underserved outcome = innovation opportunity.

---

## Step 5 — Identify the competition (the real alternatives)

What was the customer using before your product? What do they use when your product isn't available?

The competition for JTBD is not what you'd expect: Christensen found that McDonald's milkshakes competed with bananas and bagels (for the "boring morning commute" job), not other milkshakes.

```
Real alternatives customers use: [list]
Why they hired those instead: [reasons]
What they gave up: [limitations of alternatives]
```

---

## Step 6 — Output

```
**JTBD analysis for [product/feature]**

The job: When [situation], customers want to [motivation] so they can [outcome]

Functional: [core task]
Emotional: [how they want to feel]
Social: [how they want to be seen]

Top underserved outcomes (opportunity score > 10):
1. [outcome] — Imp: [X]/10, Sat: [Y]/10
2. [outcome] — Imp: [X]/10, Sat: [Y]/10

Real competition: [list]
Key insight: [the non-obvious finding]

Design implication: [what to build/prioritize/drop]
```

---

## Notes

- The job doesn't change; only the solutions do. The job of "communicating at a distance" is 150 years old — telegraph, phone, email, Slack are all hired for it
- "Hire" and "fire" are the right mental models — customers fire a product when a better-for-the-job alternative exists
- Christensen's warning: don't ask customers what they want. Observe what job they're already trying to do and what workarounds they've built
- Pairs with `/brana:swot-analysis` after defining the job — SWOT maps whether you're positioned to win at it
