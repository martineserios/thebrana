---
name: inversion
description: "Solve problems by thinking backward from failure. Instead of 'how do I succeed?', ask 'what would guarantee failure?' then avoid those things. Carl Jacobi + Charlie Munger. Use for goal setting, risk analysis, strategy, or when direct approaches aren't working."
group: thinking
keywords: [inversion, failure, risk, munger, backward-thinking, anti-goals, strategy]
allowed-tools:
  - AskUserQuestion
  - Read
  - Glob
  - Grep
status: acquired
source: "https://github.com/guia-matthieu/clawfu-skills"
acquired: "2026-06-15"
---

# Inversion

> "Invert, always invert." — Carl Jacobi
> Many problems are best solved backward. Instead of asking "How do I succeed?", ask "What would guarantee failure?" then avoid those things. — Charlie Munger

## When to Use

- **Goal setting** — define what guarantees failure, then avoid it
- **Risk analysis** — find what could destroy the project before starting
- **Decision making** — evaluate choices by examining worst outcomes
- **Problem solving** — when direct approaches aren't working
- **Strategy** — find competitive advantages by avoiding common mistakes

## Difference from Pre-Mortem

| Pre-mortem | Inversion |
|------------|----------|
| "Imagine the project failed — why?" | "What would guarantee failure if we tried?" |
| Retrospective (looking back from future failure) | Generative (designing the failure actively) |
| Good for project planning | Good for strategy, goals, and stuck problems |
| Output: risk register | Output: anti-goals + avoidance strategy |

## Steps

### 1. State your goal
Write the goal in one sentence: "I want to [outcome]."

### 2. Invert it
State the anti-goal: "I want to guarantee that I do NOT achieve [outcome]."

### 3. Design the failure actively
Ask: "If I *wanted* to fail at this, what would I do?"

Generate failure strategies across:
- **Actions to take** — what behaviors would destroy this goal?
- **Things to ignore** — what signals, feedback, or constraints would I pretend don't exist?
- **People to alienate** — whose support is critical that I'd push away?
- **Assumptions to cling to** — what false beliefs would I refuse to update?
- **Resources to misallocate** — where would I spend effort that guarantees waste?

Aim for 10-15 failure strategies. Be specific. Make them believable.

### 4. Recognize which failures you're already doing
Go through each failure strategy and ask: "Am I currently doing any of this?"

This is where inversion pays off — it surfaces current behavior that's working against the goal.

### 5. Build the avoidance strategy
For each failure strategy you identified (especially ones you're already doing):
- What's the opposite behavior?
- What specific change would eliminate this failure path?
- What early warning signal tells you you're sliding back?

### 6. Restate the goal as anti-failures
Sometimes it's clearer to define success as: "I will know I'm on track when I'm NOT doing [failure list]."

## Output Format

```
Inversion: [Goal]

Anti-goal: guarantee failure at [goal]

Top failure strategies:
1. [Failure action] — Am I doing this now? [Yes/No/Partially]
2. ...

Currently at risk:
- [Failure strategy I'm already executing]

Avoidance strategy:
- [Concrete change] → eliminates [failure path]

Restated goal (as anti-failures):
Success = not [failure 1], not [failure 2], not [failure 3]
```
