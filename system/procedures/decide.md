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

## Step 2 — Check context (optional, fast)

If task selection ("what to work on?"): run `brana backlog next 2>/dev/null | head -5`.
If ruflo is available: `mcp__ruflo__memory_search_unified(query: "{QUESTION}", namespace: "pattern", limit: 2, threshold: 0.3)`.
Skip if neither adds value for the question.

---

## Step 3 — Answer

```
**{question restated in ≤10 words}**
Do {X}. {One sentence why.}
```

No headers. No bullet lists. No "it depends" without an immediate answer. If uncertain, say "Not enough signal — try X first."
