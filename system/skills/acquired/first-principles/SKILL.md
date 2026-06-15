---
name: first-principles
description: "Bottom-up reasoning from fundamentals — strip assumptions, interrogate each one, rebuild from what's actually true."
group: thinking
keywords: [first-principles, assumptions, fundamentals, reasoning, decompose, rebuild, feynman, musk]
task_strategies: [spike, investigation]
stream_affinity: [roadmap, research]
allowed-tools:
  - Read
  - Glob
  - Grep
  - AskUserQuestion
status: experimental
source: "Aristotle — Nicomachean Ethics; Elon Musk interviews (2012–2013); Richard Feynman technique"
acquired: "2026-06-15"
---
# First Principles

**Strip everything down to what's actually true. Rebuild from there.**

Aristotle's method, popularized in engineering by Musk and in learning by Feynman. Conventional wisdom is compressed prior reasoning — first-principles forces you to re-examine whether that prior reasoning still holds.

---

## When to use

- When the conventional approach feels wrong but you can't articulate why
- When costs or constraints seem fixed but might be negotiable
- When you need a genuinely novel solution (not iteration on existing ones)
- When a complex problem seems unsolvable
- After `/brana:inversion` — inversion finds what to avoid; first-principles finds a better path

---

## Step 1 — Define the problem clearly

State the problem in one sentence without embedding a solution:
```
AskUserQuestion: "What problem are we trying to solve? (No 'by doing X' in the answer)"
```

Reject: "We need to make our deploy pipeline faster by switching to GitHub Actions"
Accept: "We need to reduce the time between code commit and production deployment"

---

## Step 2 — List all assumptions

What do you currently believe is true about this problem? Include:
- Cost assumptions ("it would cost $X")
- Technical assumptions ("we need Y to do Z")
- Process assumptions ("it always takes N days")
- Constraint assumptions ("we can't do X because Y")
- Social assumptions ("users won't accept Z")

List them all. Don't filter. Include assumptions so obvious they feel like facts.

---

## Step 3 — Interrogate each assumption

Classify each assumption:

| Type | Definition | Action |
|------|-----------|--------|
| **Fundamental** | Grounded in physics, math, or empirical fact | Keep — build from it |
| **Conventional** | True in most contexts but not inherent | Examine — when does it break? |
| **False** | Not actually true, just inherited | Discard — opens solution space |

For each Conventional or False assumption, ask:
- "Where did this belief come from?"
- "Is there evidence it's true for our specific situation?"
- "What would be possible if this weren't true?"

---

## Step 4 — Rebuild from fundamentals

Starting only from the Fundamental truths identified in Step 3:

1. What is the absolute minimum required to solve the problem?
2. What solution would you design if you had no existing system to work around?
3. What would this look like if you were building it for the first time today?

Don't iterate on the existing solution. Start fresh from the fundamentals.

---

## Step 5 — Identify the lever

What is the single assumption or constraint that, if removed, would most change the solution space?

```
**First-principles analysis of [problem]**
Key false assumption found: [X]
What it makes possible: [Y]
Recommended direction: [Z]
```

---

## Notes

- The goal is not to always do something radically different — sometimes first principles confirms the conventional approach is right
- Most useful when the conventional solution has unexplained high costs or persistent failure modes
- Feynman's test: can you explain the reasoning to a 12-year-old? If not, you're leaning on authority, not understanding
- Pair with `/brana:challenge` to stress-test the rebuilt solution
