---
name: six-thinking-hats
description: "Edward de Bono's parallel thinking framework — examine a decision from 6 distinct perspectives systematically. Use for complex decisions needing multiple viewpoints, breaking analysis paralysis, or when a decision has been approached from only one angle (usually either pure optimism or pure caution)."
group: thinking
keywords: [six-hats, de-bono, parallel-thinking, perspectives, decision, evaluation, creative, balanced]
allowed-tools:
  - AskUserQuestion
  - Read
  - Glob
  - Grep
status: acquired
source: "https://github.com/guia-matthieu/clawfu-skills"
acquired: "2026-06-15"
---

# Six Thinking Hats

> Edward de Bono's parallel thinking framework (1985). Instead of adversarial debate where people argue from fixed positions, everyone thinks in the *same direction* at the same time — switching perspectives together.

## The Six Hats

| Hat | Color | Mode | Question |
|-----|-------|------|----------|
| **White** | Data | Facts only — no opinions | What do we know? What's missing? |
| **Red** | Emotions | Gut feelings, intuitions, hunches | What do I feel about this, without justification? |
| **Black** | Caution | Risks, problems, why it won't work | What could go wrong? What are the dangers? |
| **Yellow** | Benefits | Optimism, value, why it will work | What's the best case? What's the value? |
| **Green** | Creativity | Alternatives, new ideas, lateral thinking | What else could we do? What haven't we considered? |
| **Blue** | Process | Meta-thinking, organizing the thinking | What thinking do we need? What have we concluded? |

**Key insight:** Black hat and Yellow hat are both necessary. Many decisions fail because people skip one or the other — either pure optimism (skip black) or analysis paralysis (skip yellow and green).

## When to Use

- Complex decisions that have been analyzed from only one angle
- Breaking out of a stuck debate where sides are entrenched
- Before launch — balancing optimism with caution
- When you need creative alternatives (not just evaluation)

## Sequence

Blue always opens and closes. The order of the middle four depends on the situation:

**For evaluation** (assessing an existing proposal):
Blue → White → Yellow → Black → Green → Red → Blue

**For problem-solving** (generating solutions):
Blue → White → Green → Yellow → Black → Red → Blue

**For conflict** (opposing views):
Blue → Red → White → Yellow → Black → Green → Blue

## Steps

### Blue (open) — set up
State what we're thinking about. Identify which sequence to use. Time-box each hat.

### White — data
List what is known as fact (no interpretation). List what information is missing and would change the analysis.

### Yellow/Black/Green/Red — analysis (per sequence)
For each hat, stay strictly in that mode. No mixing — if a risk surfaces during Yellow, note it and return to it in Black.

**Common mistakes:**
- Black hat dressed as White ("the data shows it will fail" — that's Black, not White)
- Skipping Red ("gut feelings aren't relevant") — they are; surfacing them explicitly prevents them from leaking into White or Black
- Thin Green ("we could do X instead") — Green should generate 3+ alternatives minimum

### Blue (close) — synthesis
What has the thinking revealed? What's the conclusion? What thinking still needs to happen?

## Output Format

```
Six Thinking Hats: [Topic/Decision]
Sequence used: [evaluation / problem-solving / conflict]

🤍 White (facts):
  Known: [list]
  Missing: [list]

🟡 Yellow (benefits):
  [3-5 genuine upsides]

⬛ Black (caution):
  [3-5 specific risks/problems]

🟢 Green (alternatives):
  [3+ alternatives or modifications not yet considered]

❤️ Red (intuition):
  [gut feeling, no justification required]

🔵 Blue (synthesis):
  Key insight: [what the six perspectives revealed that any one alone wouldn't]
  Conclusion: [decision or next step]
  Remaining: [what still needs thinking]
```
