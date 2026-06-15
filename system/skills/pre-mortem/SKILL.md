---
name: pre-mortem
description: "Imagine the project already failed — work backward to find out why. Gary Klein's prospective hindsight technique. Use before launching, before committing resources, or when everyone agrees the plan is great (overconfidence signal). Surfaces failure modes that forward-looking risk analysis misses."
group: thinking
keywords: [pre-mortem, failure-modes, risk, prospective-hindsight, launch, planning, assumptions]
allowed-tools:
  - AskUserQuestion
  - Read
  - Glob
  - Grep
status: acquired
source: "https://github.com/guia-matthieu/clawfu-skills"
acquired: "2026-06-15"
---

# Pre-Mortem

> Imagine your project has failed spectacularly — then work backward to identify why. Gary Klein's "prospective hindsight" technique.

## When to Use

- **Before launching** a product, campaign, or major initiative
- **Before making** an important decision (hiring, investment, partnership)
- **When overconfident** and everyone agrees the plan is great
- **Before committing resources** to a significant undertaking
- **In team planning** to surface concerns people hesitate to share

## Methodology

**Source:** Gary Klein (1989) — prospective hindsight increases accuracy of identifying failure reasons by ~30% vs. conventional risk analysis.

**Core principle:** The future feels distant; the past feels real. Imagining an event has *already occurred* dramatically improves our ability to explain it.

## Steps

### 1. Set the scene
State clearly: "It is [date 12 months from now]. The project/decision has failed completely. Not a partial miss — a spectacular failure. The postmortem has been written."

### 2. Generate failure causes (diverge)
For each domain, ask: "What caused this?"

- **Execution failures** — what did the team do wrong or fail to do?
- **Assumption failures** — what did we believe that turned out to be false?
- **External surprises** — what changed in the market/environment we didn't anticipate?
- **Resource failures** — where did time, money, or people run out?
- **Political/stakeholder failures** — who blocked, withdrew, or changed direction?

Generate 3-5 causes per domain. Don't filter during this phase — even low-probability causes belong here.

### 3. Rank by impact × probability
For each cause: score impact (1-3) × probability (1-3) = priority score. Focus on 6+ scores.

### 4. Write the obituary
Draft a 2-3 sentence "project obituary" — what the post-mortem would say. This makes the failure visceral and real, triggering additional recall.

### 5. Design preventions (converge)
For each high-priority cause:
- What early warning signal would have told us this was happening?
- What could we change in the plan today to prevent or mitigate it?
- Who owns monitoring this risk?

### 6. Update the plan
Output: list of 3-5 concrete plan changes, each linked to the failure cause it prevents.

## Output Format

```
Pre-Mortem: [Project/Decision Name]
Date: [today]

Scenario: It is [date]. [Project] has failed.

Top failure causes (by priority):
1. [Cause] — Impact: X, Probability: Y, Score: Z
   Prevention: [concrete action]
   Signal: [early warning indicator]
2. ...

Plan changes:
- [Change 1]: addresses [cause(s)]
- [Change 2]: addresses [cause(s)]

Updated confidence: [higher/same/lower] — why: [one sentence]
```
