---
name: decide
description: "Decision support — criteria, scenarios, patterns, recommendation."
effort: low
keywords: [decision, recommendation, what-to-do, prioritize, choose, next, options, trade-off]
task_strategies: [spike, investigation]
stream_affinity: [roadmap, research]
argument-hint: "[question or options, e.g. 'should I do A or B' / 'what to work on next']"
group: thinking
model: sonnet
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - AskUserQuestion
  - mcp__ruflo__memory_search_unified
  - mcp__ruflo__autopilot_predict
  - ToolSearch
status: stable
growth_stage: evergreen
---
# Decide — Fast Decision

**One sentence in, one recommendation out.**

---

## Step 1 — Get the question

Use the skill arg if provided. If the conversation makes the question obvious, use that (Recommended). Otherwise ask:

```
AskUserQuestion: "What's the decision? One sentence."
```

---

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__memory_search_unified")

## Step 2 — Detect complexity

Before answering, classify the question:

**Simple** (fast lane → skip to Step 4):
- One option to evaluate (go/no-go, yes/no)
- Task selection ("what to work on next?")
- Urgency ("should I do X now or later?")

**Complex** (ask first):
- 2+ named alternatives (A vs B vs C)
- Strategic direction (which product area, which market, which architecture)
- Multi-criteria with real trade-offs (cost vs speed vs quality)
- High stakes, hard to reverse

For **complex** questions, surface the right framework before answering:

```
AskUserQuestion:
  question: "This has multiple alternatives/dimensions. How deep do you want to go?"
  header: "Depth"
  options:
    - label: "Quick take — best guess now"
      description: "I give a recommendation with brief reasoning. Fast, opinionated."
    - label: "Decision matrix — weighted scoring"
      description: "We score each option against criteria with weights. Explicit, defensible. Best for vendor/tool/strategy selection."
    - label: "SWOT first — strategic framing"
      description: "Analyze strengths/weaknesses/opportunities/threats before deciding. Best for product or business direction."
    - label: "Six hats — full perspective sweep"
      description: "Run White/Yellow/Black/Green/Red/Blue lenses. Best for decisions that need both optimism and caution."
```

If user picks quick take → proceed to Step 4.
If user picks decision matrix → invoke `decision-matrix` skill via Skill tool.
If user picks SWOT → invoke `swot-analysis` skill via Skill tool.
If user picks six hats → invoke `six-thinking-hats` skill via Skill tool.

---

## Step 3 — Check context (optional, fast)

If task selection ("what to work on?"): run `brana backlog next 2>/dev/null | head -5`.
If ruflo is available: `mcp__ruflo__memory_search_unified(query: "{QUESTION}", namespace: "pattern", limit: 2, threshold: 0.3)`.
Skip if neither adds value for the question.

---

## Step 4 — Answer

```
**{question restated in ≤10 words}**
Do {X}. {One sentence why.}
```

No headers. No bullet lists. No "it depends" without an immediate answer. If uncertain, say "Not enough signal — try X first."
