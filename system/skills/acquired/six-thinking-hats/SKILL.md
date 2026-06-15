---
name: six-thinking-hats
description: "Six parallel thinking perspectives — White/Red/Black/Yellow/Green/Blue — to separate facts, feelings, risks, benefits, creativity, and process."
group: thinking
keywords: [six-hats, parallel-thinking, de-bono, perspectives, evaluation, creativity, decision]
task_strategies: [spike, investigation]
stream_affinity: [roadmap, research]
allowed-tools:
  - Read
  - Glob
  - Grep
  - AskUserQuestion
status: experimental
source: "Edward de Bono — Six Thinking Hats (1985)"
acquired: "2026-06-15"
---
# Six Thinking Hats

**Six perspectives, one at a time. No mixing.**

Edward de Bono's parallel thinking framework. The key insight: most group decisions fail because people think in different modes simultaneously — one person doing risk analysis, another doing creative thinking, another defending a position. Six Hats separates these modes so everyone thinks the same way at the same time.

---

## The Hats

| Hat | Color | Mode | Question |
|-----|-------|------|----------|
| **White** | ⬜ | Facts & data | What do we know? What's missing? |
| **Red** | 🟥 | Feelings & intuition | What's my gut reaction? What feels wrong? |
| **Black** | ⬛ | Caution & risks | What could go wrong? What are the downsides? |
| **Yellow** | 🟨 | Optimism & value | What's the best case? What's genuinely valuable here? |
| **Green** | 🟩 | Creativity & alternatives | What other options exist? What if we tried X? |
| **Blue** | 🟦 | Process & facilitation | What are we doing? What's the next step? |

---

## When to use

- When a team is stuck in debate (everyone arguing from mixed modes simultaneously)
- When a decision needs both optimism and caution explored equally
- When you want to ensure a blind spot (e.g., creativity, feelings) gets explicit attention
- High-stakes evaluations where one perspective usually dominates
- Pairs with `/brana:decision-matrix` for structured scoring after the hat sweep

---

## Step 1 — Frame the question

What are we evaluating or deciding?

```
AskUserQuestion: "What decision or situation are we thinking through with Six Hats?"
```

---

## Step 2 — Choose a sequence

| Scenario | Recommended sequence |
|----------|---------------------|
| **Evaluating an existing proposal** | Blue → White → Yellow → Black → Green → Red → Blue |
| **Solving a problem** | Blue → White → Green → Yellow → Black → Red → Blue |
| **Managing conflict** | Blue → Red → White → Yellow → Black → Green → Blue |
| **Quick decision** | Blue → White → Black → Yellow → Blue |

Ask if unsure:
```
AskUserQuestion:
  question: "What's the primary goal of this thinking session?"
  options:
    - "Evaluate a proposal"
    - "Solve a problem"
    - "Resolve conflict or disagreement"
    - "Quick decision check"
```

---

## Step 3 — Run each hat

For each hat in the sequence, think **only** in that mode. Suppress all other modes.

**⬜ White Hat — Facts**
- What data do we have?
- What data do we need?
- What are the known facts (not interpretations)?
- What is uncertain or unknown?

**🟥 Red Hat — Feelings**
- What is your gut reaction?
- What excites you about this?
- What makes you uneasy, even if you can't explain why?
- No justification needed — feelings are data.

**⬛ Black Hat — Caution**
- What could go wrong?
- What are the logical weaknesses?
- What assumptions might be false?
- What risks haven't been addressed?
- (This is the most overused hat — limit it to this slot only)

**🟨 Yellow Hat — Value**
- What is genuinely valuable here?
- What's the best realistic outcome?
- What opportunities does this create?
- What strengths does this have?

**🟩 Green Hat — Creativity**
- What alternatives haven't been considered?
- What if we changed [constraint X]?
- What's the unconventional approach?
- Can we combine existing ideas differently?

**🟦 Blue Hat — Process**
- At start: What are we trying to achieve? What's the sequence?
- At end: What did we conclude? What's the next action?

---

## Step 4 — Synthesize

After the sequence, the Blue Hat closes:
```
**Six Hats synthesis for [topic]**

Facts established (White): [key data points]
Gut signals (Red): [notable feelings / instincts]
Key risks (Black): [top 2-3]
Core value (Yellow): [strongest case for]
Alternatives surfaced (Green): [new options]

Conclusion: [decision or next step]
```

---

## Notes

- The Black Hat is not "being negative" — it's doing quality control. Don't suppress it.
- The Red Hat gives permission to voice intuition without justification — critical for surfacing what formal analysis misses
- In solo use: spend 3–5 minutes per hat in writing before moving to the next
- Don't wear two hats at once — if someone says "I know we're in Yellow but the risk is..." redirect to Black Hat time
- De Bono's insight: parallel thinking removes ego from disagreement — everyone is wearing the same hat, so disagreement is the hat disagreeing, not the person
