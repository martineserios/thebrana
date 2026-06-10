---
name: retrospective
description: Store a learning — classify type, route to canonical destination. Use after discoveries, unexpected issues, workarounds, or when a reusable pattern emerges.
effort: low
keywords: [learning, pattern, discovery, workaround, knowledge]
task_strategies: [feature, bug-fix, refactor, spike]
stream_affinity: [roadmap, tech-debt, research]
argument-hint: "[learning text]"
group: learning
model: haiku
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
  - mcp__ruflo__memory_search
  - ToolSearch
status: stable
growth_stage: evergreen
---
# Retrospective

Store a learning in the memory taxonomy. Classifies the input by type, then routes
to the canonical destination. No ruflo dependency — flat files are primary.

Spec: [memory-taxonomy-ddd.md](../../../docs/architecture/features/memory-taxonomy-ddd.md)
      [memory-taxonomy-sdd.md](../../../docs/architecture/features/memory-taxonomy-sdd.md)

---

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__memory_search")

## Step 1 — Collect the learning

If `$ARGUMENTS` is non-empty, use it as the learning text. Otherwise ask:
> "What did you learn? Describe the situation and the finding."

---

## Step 2 — Classify

Apply the decision tree in order. Stop at first match.

```
1. Is this ephemeral — only useful for resuming this session?
   → Session state (skip retrospective; write via session-end hook)

2. Does this say "always X" or "never Y" with no context needed to apply it?
   → Rule

3. Is this a why-we-chose-X architectural or strategic choice with explicit tradeoffs?
   → Decision

4. Is this a pointer to where something lives in an external or cross-project system?
   → Reference

5. Is this a reusable solution to a recurring problem shape?
   → Pattern

6. Everything else — domain understanding, research finding, conceptual model
   → Knowledge
```

Set `type`, `destination`, and `gate` (auto | human) from the table:

| Type | Destination | Gate |
|------|------------|------|
| Rule | `system/rules/` — draft only, human places | human |
| Decision | `docs/architecture/decisions/ADR-NNN-*.md` — stub, human commits | human |
| Reference | `~/.claude/memory/portfolio.md` | auto |
| Pattern | `~/.claude/projects/{project}/memory/pattern_{slug}_{date}.md` | auto (after transferability filter) |
| Knowledge | `~/.claude/memory/knowledge-staging.md` | auto |
| Session | native memory dir — skip, handled by session-end | auto |

**Tie-breaking:** If two types are plausible, prefer lower-gate type (Pattern over Rule).
Note the ambiguity in the draft so the user can override.

---

## Step 3 — Format the draft

### Rule draft

```markdown
<!-- Draft rule — review, adjust, then place in system/rules/{name}.md -->
# {Rule Name}

{directive: "Always X" or "Never Y" — one sentence, no context needed to apply}

**Why:** {the incident or principle that established this}
**How to apply:** {when this fires, edge cases}
```

### Pattern draft

**Before drafting**, apply the transferability filter:
> *"Would this pattern apply if I were working on a completely different codebase with a different client?"*
- **No** → reclassify as Knowledge or field note. Do not use the pattern destination.
- **Borderline** → proceed with `confidence: 0.4`
- **Yes** → proceed with `confidence: 0.5`

```markdown
---
name: {pattern-name-slug}
description: {one-line summary — used to decide relevance in future sessions, be specific}
metadata:
  type: pattern
  confidence: {0.5 | 0.4 for borderline}
  source_task: {task-id or "manual-{YYYY-MM-DD}"}
  created: {YYYY-MM-DD}
  transferable: true
---

**Problem:** {one sentence — the situation that triggers this pattern}
**Solution:** {what to do, concrete enough to apply without context}
**Why:** {evidence — past incident, test result, or principle}
```

### Knowledge draft

```markdown
## {topic-slug}

**Claim:** {the knowledge — a fact, model, or finding}
**Source:** {doc, session, or external ref}
**Confidence:** {low | medium | high}
**Added:** {today}
**Promote to:** {path/to/dimension-doc.md | portfolio.md | MEMORY.md}
**Promoted:** —
```

### Decision draft (ADR stub)

```markdown
# ADR-NNN: {title}

**Status:** Proposed
**Date:** {today}

## Context
{why this decision was needed}

## Decision
{what was decided}

## Consequences
{tradeoffs accepted}

## Non-actions
{what was explicitly ruled out}
```

### Reference draft

One-line entry for `portfolio.md`:
```
- {system name}: {what it contains / why it matters} — {URL or path}
```

---

## Step 4 — Cap check (auto-gate types only)

Before writing, check destination capacity:

**Pattern — dedup check (replaces cap):**
```
mcp__ruflo__memory_search(query: "{pattern problem + solution summary}", namespace: "pattern", limit: 1, threshold: 0.85)
```
- Similarity ≥ 0.85: near-duplicate exists — skip write, note the existing key.
- No match / MCP unavailable: proceed to write.
No cap, no pruning. Per-pattern files scale without maintenance overhead.

**knowledge-staging.md:**
```bash
count=$(grep -c "^## " ~/.claude/memory/knowledge-staging.md 2>/dev/null || echo 0)
```
- ≥20: warn "knowledge-staging.md at {N}/30 — run `/brana:memory review` to promote stale entries"
- =30: block. Require promotion or deletion of ≥1 entry first.

**MEMORY.md (for Reference type):**
```bash
count=$(wc -l < ~/.claude/projects/-home-martineserios-enter-thebrana-thebrana/memory/MEMORY.md 2>/dev/null || echo 0)
```
- ≥180: warn "MEMORY.md at {N}/200 lines"
- ≥195: block. No new entries until trimmed.

---

## Step 5 — Write (or gate)

### Human-gated types (Rule, Decision)

```
AskUserQuestion:
  question: "Classified as {type}. Review the draft and confirm routing."
  header: "Memory routing"
  options:
    - label: "Approve — {type} → {destination} (Recommended)"
      description: "Accept the classified type and route to the suggested destination."
    - label: "Override type → Pattern"
      description: "Reclassify as Pattern and route to pattern memory."
    - label: "Override type → Knowledge"
      description: "Reclassify as Knowledge and route to knowledge staging."
    - label: "Skip — don't store"
      description: "Discard this learning — don't store anywhere."
```

On "Approve":
- **Rule:** Display the draft text. Instruct: "Place this in `system/rules/{name}.md` and commit it yourself. I won't auto-write to rules/."
- **Decision:** Write the ADR stub to `docs/architecture/decisions/ADR-NNN-{slug}.md` (next available NNN). Instruct: "Review the stub, adjust, and commit."

### Auto-gated types (Pattern, Knowledge, Reference)

Write `draft` content to destination:

**Pattern → `~/.claude/projects/{project-hash}/memory/pattern_{slug}_{YYYY-MM-DD}.md`:**

Write the draft (with frontmatter) to a new per-pattern file. Use Write tool.
Activate the sentinel first so `feedback-gate.sh` passes through:
```bash
touch /tmp/brana-close-active
# ... write pattern file ...
rm -f /tmp/brana-close-active
```

Do NOT append to MEMORY.md. Pattern files are findable via ruflo semantic search.
MEMORY.md entries are added only at explicit human promotion (recurrence ≥ 3 sessions).

**Knowledge → `~/.claude/memory/knowledge-staging.md`:**
```bash
if [ ! -f ~/.claude/memory/knowledge-staging.md ]; then
  echo "# Knowledge Staging" > ~/.claude/memory/knowledge-staging.md
  echo "" >> ~/.claude/memory/knowledge-staging.md
  echo "<!-- cap: 30 | warn-at: 20 | stale-after: 30 days -->" >> ~/.claude/memory/knowledge-staging.md
fi
```
Prepend the draft after the file header.

**Reference → `~/.claude/memory/portfolio.md`:**
Append the one-line entry to the appropriate section. If section not found, append to end.

---

## Step 6 — Fallback chain

If a destination is unavailable (file locked, dir missing, write denied):

```
Pattern fallback:  if project memory dir missing → write to ~/.claude/memory/pattern_{slug}_{date}.md
Knowledge fallback: knowledge-staging.md → MEMORY.md inline with [KNOWLEDGE] prefix
Reference fallback: portfolio.md → MEMORY.md inline
Rule/Decision: no fallback — human-gated, display draft only
```

Log any fallback to `~/.claude/memory/fallback-log.md`:
```
{date} | {type} | intended: {destination} | actual: MEMORY.md | reason: {error}
```

---

## Step 7 — Confirm

Report what was stored and where:
```
Stored: {type} → {destination}
Title:  {pattern/knowledge/decision title}
Gate:   {auto | human-approved | human-display-only}
```

---

## Step 8 — Promotion tracking (patterns only)

After storing, check if any patterns recalled this session warrant promotion.

Search per-pattern files for low-confidence entries:
```bash
grep -rl "confidence: 0\.[45]" ~/.claude/projects/{project-hash}/memory/pattern_*.md 2>/dev/null
```

For each recalled pattern that **was useful** this session:
- Note the recall mentally. If a pattern has been recalled and useful ≥3 sessions: surface it for promotion.
- Promotion path: user approves → create `feedback_{slug}.md` + add entry to MEMORY.md
  (always-loaded tier). Update the per-pattern file frontmatter: `confidence: 0.7`.

For each recalled pattern that **was harmful or misleading**:
- Update the per-pattern file frontmatter: `confidence: 0.2` (suspect).

**Skip this step** if no patterns were recalled or user wants to skip.

---

## Step 9 — Backup

```bash
"$HOME/.claude/scripts/backup-knowledge.sh" 2>/dev/null || true
```

---

## Rules

- **Placement in `system/rules/` is always manual.** Display draft, instruct user. Never write there automatically.
- **All learnings route through the taxonomy.** No catch-all files; no feedback_ prefix files.
- **Never overwrite per-pattern files.** Each pattern is its own file; knowledge-staging.md is append-only.
- **Classify honestly.** When uncertain, prefer Pattern over Rule (lower gate = fewer blockers).
- **Ask for clarification** if the learning is ambiguous — don't guess the type.
