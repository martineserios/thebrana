---
name: critical-thinking-logical-reasoning
description: "Surface hidden assumptions, detect logical fallacies, examine evidence quality, and stress-test arguments before committing to them."
group: thinking
keywords: [critical-thinking, logical-reasoning, fallacies, assumptions, evidence, argument, analysis, reasoning]
task_strategies: [spike, investigation]
stream_affinity: [roadmap, research]
allowed-tools:
  - Read
  - Glob
  - Grep
  - AskUserQuestion
status: experimental
source: "Richard Paul & Linda Elder — Critical Thinking (2006); Kahneman — Thinking Fast and Slow (2011); Aristotle — Prior Analytics"
acquired: "2026-06-15"
---
# Critical Thinking & Logical Reasoning

**Find what's wrong with the argument before you commit to it.**

Critical thinking is not skepticism for its own sake — it's the discipline of examining the quality of reasoning before acting on it. The goal is to catch flawed logic, hidden assumptions, and weak evidence before they become expensive decisions.

---

## When to use

- Evaluating a proposal, plan, or recommendation
- When an argument sounds compelling but feels off
- Before accepting data-driven claims
- When debugging a persistent wrong belief in a team
- After research — to evaluate what you found before applying it
- Pairs with `/brana:challenge` for adversarial review; `/brana:first-principles` for rebuilding from what's actually true

---

## Step 1 — Identify the claim

What is being asserted?

```
AskUserQuestion: "What claim, argument, or reasoning are we examining?"
```

State it in the clearest possible form. Often the act of stating a claim precisely already reveals its weakness.

---

## Step 2 — Surface hidden assumptions

Every argument rests on assumptions. List them all:

**Existential assumptions** — "X exists" or "X is real"
- Example: "Our users are power users" assumes that power users are a significant segment

**Causal assumptions** — "X causes Y"
- Example: "More features = more retention" assumes features are the bottleneck for retention

**Comparative assumptions** — "X is better than Y"
- Example: "Rewriting will be faster" assumes the rewrite won't hit the same problems

**Scoping assumptions** — "This applies to all of / most of / some of X"
- Example: "Users want this" means... how many? Which users?

For each assumption:
- Is it stated or hidden?
- What evidence supports it?
- What would change if it's wrong?

---

## Step 3 — Examine evidence quality

For each claim, ask:

| Question | What to look for |
|----------|-----------------|
| **Source** | Primary source or hearsay? Who funded the research? |
| **Sample** | How big? How representative? Self-selected? |
| **Method** | Controlled? Correlation confused for causation? |
| **Recency** | Is this still true? Context may have changed |
| **Completeness** | What evidence AGAINST the claim exists? |

Evidence strength scale:
- **Strong**: large controlled study, multiple independent replications
- **Moderate**: single study, observational data, expert consensus
- **Weak**: anecdote, single data point, self-report, authority claim
- **None**: assertion without evidence

---

## Step 4 — Check for logical fallacies

Common fallacies in technical and business reasoning:

| Fallacy | Pattern | Example |
|---------|---------|---------|
| **Ad hominem** | Attack the person, not the argument | "Of course they'd say that, they're from [company]" |
| **Appeal to authority** | Authority = truth | "Google does it this way" |
| **False dichotomy** | Only two options | "We either rewrite or stay stuck forever" |
| **Slippery slope** | One step inevitably leads to extreme | "If we add this exception, everything will become exceptions" |
| **Strawman** | Misrepresent the opposing view | "So you're saying we should never refactor?" |
| **Correlation/causation** | A happens with B, therefore A causes B | "Users who use feature X retain better, so feature X causes retention" |
| **Sunk cost** | Past investment justifies future investment | "We've already spent 3 months on this" |
| **Availability heuristic** | Recent/memorable = common | "I've seen this bug before so it must be frequent" |
| **Confirmation bias** | Seeking evidence that confirms, ignoring disconfirming | Only citing studies that support the conclusion |
| **Base rate neglect** | Ignoring prior probability | "Our competitor failed at this but we're better" |

Mark each fallacy found: [claim] → [fallacy type] → [why it's wrong here]

---

## Step 5 — Evaluate the argument structure

Is the reasoning valid? (Does the conclusion follow from the premises?)
Is the reasoning sound? (Are the premises true AND does the conclusion follow?)

```
Premise 1: [X]
Premise 2: [Y]
∴ Conclusion: [Z]

Valid? [yes/no] — does Z follow from X and Y?
Sound? [yes/no] — are X and Y actually true?
```

An argument can be valid (correct structure) but unsound (false premises). Most flawed reasoning is unsound, not invalid.

---

## Step 6 — Output

```
**Critical thinking analysis of [claim/argument]**

Core claim: [restated precisely]

Hidden assumptions found: [N]
  Critical: [most load-bearing assumption]
  Status: [supported/unsupported/false]

Evidence quality: [strong/moderate/weak/none]
  Key gap: [what evidence is missing]

Fallacies detected: [list]

Argument structure: [valid/invalid] + [sound/unsound]

Verdict:
  Accept as is / Accept with caveats / Reject / Needs more evidence
  Key condition: [what would change the verdict]
```

---

## Notes

- The goal is not to win arguments — it's to make better decisions by reasoning better
- Steel-man before attacking: state the strongest version of the opposing argument first
- Kahneman's System 1/System 2: most reasoning errors come from System 1 (fast, intuitive) presenting conclusions to System 2 (slow, analytical) without flagging they're conclusions
- "I believe X" is not the same as "there is evidence for X" — distinguish confidence from evidence
- Strong critical thinking produces "I was wrong" as often as "they're wrong"
- Pair with `/brana:brainstorm` after debunking — critique clears the space; brainstorm fills it
