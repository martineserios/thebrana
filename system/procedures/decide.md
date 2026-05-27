
# Decide — Lightweight Decision Support

One command to answer: **What should I do, and why?**

Use when facing an open question ("what to work on next?"), a binary choice ("A or B?"), or an approach decision ("how should I tackle this?"). Outputs one clear recommendation with brief reasoning — not a long analysis.

---

## Input

The question or choice comes from one of three sources (in priority order):

1. **Skill args** — user passed the question directly: `/brana:decide should I refactor now or ship first?`
2. **Conversation context** — the last user message implies a decision is pending
3. **No context** — ask

If source 1 or 2 is clear, skip to Step 2. If ambiguous or absent, run Step 1.

---

## Step 1 — Clarify (only if needed)

```
AskUserQuestion:
  question: "What's the decision? Describe the options or the open question in one sentence."
```

---

## Step 2 — Gather context in parallel

Run all three in parallel:

**A. Backlog state** (current priorities and active work):
```bash
brana backlog query --status in_progress 2>/dev/null | head -20
brana backlog next 2>/dev/null | head -10
```

**B. Memory — relevant patterns:**
```
mcp__ruflo__memory_search_unified(
  query: "{DECISION_QUESTION}",
  namespace: "pattern",
  limit: 3,
  threshold: 0.25
)
```
Suppress results below 0.25 similarity. If no results, skip.

**C. Autopilot prediction (shadow):**
```
mcp__ruflo__autopilot_predict()
```
Surface prediction as data point, not directive.

**Fallback:** If ruflo MCP is unavailable, skip B and C. Proceed with backlog state only.

---

## Step 3 — Think through the decision

Work through four angles silently (do not output this analysis — it's internal scaffolding):

1. **Criteria** — What matters most here? (urgency, effort, reversibility, dependencies, momentum)
2. **Scenarios** — For each option: what's the best case, worst case, and most likely outcome?
3. **Patterns** — What do past sessions or memory patterns suggest about this type of decision?
4. **Good practices** — Does a known brana rule, field note, or principle apply?

---

## Step 4 — Output

Present a tight recommendation:

```markdown
## Decision: {restated question in one line}

**Recommendation:** {one sentence — what to do}

**Why:** {2-3 sentences max — the key reason, the main trade-off acknowledged, any relevant pattern}

{if autopilot prediction is non-trivial and aligns or conflicts:}
**Autopilot (shadow):** {action} (confidence: {N}) — {agree/conflicts with recommendation}
```

### Output rules

- Recommendation is a single, unambiguous sentence: "Do X" or "Pick Y over Z."
- Why is 2-3 sentences. No bullet walls. No exhaustive trade-off tables.
- If the right answer is genuinely unclear, say so: "Not enough signal — try X to reduce uncertainty before committing."
- If the question is actually a task-selection problem ("what to work on?"), recommend the highest-priority unblocked task and say why — don't just list options.
- No markdown headers beyond the template above. Keep it fast to read.

---

## Rules

1. **One recommendation.** Never hedge with "it depends" without immediately saying what it depends on and giving a conditional answer.
2. **Read-only.** No file edits, no task creation, no commits. Observe and advise only.
3. **Fast.** This is a 30-second skill. If the analysis is taking longer, you're over-thinking it.
4. **Honest uncertainty.** If you lack signal, say so explicitly rather than manufacturing confidence.
