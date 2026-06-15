---
name: first-principles
description: "Break a problem down to its fundamental truths, then reason up from there. Aristotle's method modernized by Musk. Use when facing 'impossible' problems, challenging industry assumptions everyone accepts, or when iteration on existing solutions isn't enough."
group: thinking
keywords: [first-principles, assumptions, decomposition, constraints, innovation, fundamentals, reasoning]
allowed-tools:
  - AskUserQuestion
  - Read
  - Glob
  - Grep
status: acquired
source: "https://github.com/guia-matthieu/clawfu-skills"
acquired: "2026-06-15"
---

# First Principles Thinking

> Break down complex problems to their fundamental truths, then reason up from there.
> "Boil things down to the most fundamental truths and say, 'What are we sure is true?' ... and then reason up from there." — Elon Musk

## When to Use

- **Facing an "impossible" problem** where conventional solutions don't work
- **Challenging industry assumptions** everyone accepts as truth
- **Cost/pricing analysis** to find dramatic savings
- **Product innovation** when iterating on existing solutions isn't enough
- **Strategic decisions** where analogies to other companies may mislead
- **Breaking mental blocks** when stuck in conventional thinking

## The Contrast: Analogy vs First Principles

| Reasoning by analogy | First principles |
|---------------------|-----------------|
| "Batteries cost $600/kWh because that's industry standard" | "What are batteries actually made of? Steel, nickel, cobalt... at commodity prices that's $80/kWh" |
| "We can't do X because no one has" | "What would X require? Is any requirement actually impossible?" |
| Fast, low-effort | Slow, high-effort |
| Iterates on existing | Can produce step-change |

Use analogy for ordinary decisions. Reserve first principles for when iteration is failing.

## Steps

### 1. Define the problem precisely
State the problem in one sentence. Avoid framing it in terms of existing solutions.

### 2. List all assumptions
Write down every belief you hold about this problem:
- Industry norms ("this is how it's always done")
- Resource constraints ("we can't afford X")
- Technical constraints ("X isn't possible")
- Market constraints ("customers won't pay for X")

Don't filter. Get everything on paper.

### 3. Interrogate each assumption
For each assumption, ask:
- **Is this actually true?** What's the evidence?
- **Why does this constraint exist?** Is it physics, economics, or just convention?
- **What would have to be true for this constraint not to exist?**

Mark each as: **Fundamental** (truly immovable) / **Conventional** (accepted but challengeable) / **False** (wrong, update immediately)

### 4. Rebuild from what's fundamental
Starting only from the **Fundamental** truths:
- What solutions are now possible that weren't when conventional assumptions held?
- What would the simplest possible solution look like from first principles?
- What intermediate steps lead there?

### 5. Identify the lever
Which challenged assumption, if acted on, produces the biggest change in what's possible?

## Output Format

```
First Principles: [Problem Statement]

Assumptions identified: [N]
- Fundamental (immovable): [list]
- Conventional (challenged): [list with why it's conventional, not physical]
- False (update now): [list]

From fundamentals only, this becomes possible:
- [Insight 1]
- [Insight 2]

Key lever: [which assumption to challenge first and why]

Next step: [concrete action that tests the key lever]
```
