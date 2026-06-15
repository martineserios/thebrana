---
name: second-order-thinking
description: "Think beyond immediate consequences — map the chain reactions of decisions. Howard Marks + Charlie Munger. Use for strategic decisions, policy/rule changes, product decisions where behavior will shift, or any time 'and then what?' matters."
group: thinking
keywords: [second-order, consequences, chain-reaction, strategy, downstream-effects, unintended-consequences, marks, munger]
allowed-tools:
  - AskUserQuestion
  - Read
  - Glob
  - Grep
status: acquired
source: "https://github.com/guia-matthieu/clawfu-skills"
acquired: "2026-06-15"
---

# Second-Order Thinking

> "First-level thinking says, 'This is a good company, let's buy.' Second-level thinking says, 'This is a good company, but everyone thinks it's great so it's overpriced. Sell.'" — Howard Marks

Most people stop at first-order (the immediate effect). Second-order thinkers ask "and then what?" until the chain of consequences is visible — including the ones that reverse the first-order conclusion.

## When to Use

- **Strategic decisions** where long-term consequences matter
- **Policy/rule changes** that will trigger behavioral responses
- **Competitive moves** where others will react
- **Product decisions** where user behavior will shift
- **Avoiding unintended consequences** in any domain

## The Levels

| Level | Question | Example |
|-------|----------|---------|
| 0 | What do we do? | "Lower prices" |
| 1st order | What happens immediately? | "More customers buy" |
| 2nd order | What does that trigger? | "Competitors lower prices too" |
| 3rd order | What does that trigger? | "Race to bottom, margins destroyed" |
| 4th order | Where does it stabilize? | "Consolidation — only largest survive" |

The interesting insight is usually at 2nd or 3rd order.

## Steps

### 1. State the decision
"We are going to [action]."

### 2. Map first-order effects
List 3-5 things that happen directly and immediately as a result.

### 3. For each first-order effect, ask "and then what?"
Push to second and third order for each. Some chains are short; some cascade. Follow the interesting ones.

Questions to push deeper:
- **Who reacts?** Customers, competitors, regulators, partners, employees?
- **How do incentives change?** What behavior becomes rational that wasn't before?
- **What gets created that didn't exist?** New markets, new problems, new actors?
- **What gets destroyed?** Existing behaviors, relationships, business models?
- **What reverses?** Does the first-order benefit eventually reverse at 3rd order?

### 4. Identify the non-obvious consequences
Mark effects that:
- Reverse the first-order benefit
- Weren't visible from the starting point
- Affect actors who weren't part of the original analysis
- Create a new problem that requires a new solution

### 5. Update the decision
Given the full consequence map:
- Is the original decision still correct?
- What modification prevents the worst non-obvious consequences?
- What early signal would tell us we're entering a bad 2nd-order path?

## Output Format

```
Second-Order Analysis: [Decision]

1st order effects:
- [Effect 1] → 2nd: [what triggers] → 3rd: [where it leads]
- [Effect 2] → 2nd: [what triggers]
- ...

Non-obvious consequences:
- [Consequence] — affects [who], appears at [timeframe]
- [Reversal]: first-order benefit [X] reverses because [chain]

Decision update:
- Original: [proceed / don't proceed / unclear]
- After 2nd-order analysis: [updated stance]
- Modification: [what to change to avoid worst chains]
- Early warning signal: [what to watch]
```
