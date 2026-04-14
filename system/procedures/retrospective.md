
# Retrospective

Store a learning in the memory taxonomy. Classifies the input by type, then routes
to the canonical destination. No ruflo dependency — flat files are primary.

Spec: [memory-taxonomy-ddd.md](../../docs/architecture/features/memory-taxonomy-ddd.md)
      [memory-taxonomy-sdd.md](../../docs/architecture/features/memory-taxonomy-sdd.md)

---

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
| Pattern | `~/.claude/memory/patterns.md` | auto |
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

```markdown
## {pattern-name-slug}

**Problem:** {one sentence — the situation that triggers this pattern}
**Solution:** {what to do, concrete enough to apply without context}
**Why:** {evidence — past incident, test result, or principle}
**Confidence:** quarantine
**Source:** {task-id or YYYY-MM-DD}
**Added:** {today}
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

**patterns.md:**
```bash
count=$(grep -c "^## " ~/.claude/memory/patterns.md 2>/dev/null || echo 0)
```
- ≥40: warn "patterns.md at {N}/50 — consider pruning quarantine entries"
- =50: block. Show 5 oldest quarantine entries. Ask user to delete ≥1 before proceeding.

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
    - "Approve — {type} → {destination}"
    - "Override type → Pattern"
    - "Override type → Knowledge"
    - "Skip — don't store"
```

On "Approve":
- **Rule:** Display the draft text. Instruct: "Place this in `system/rules/{name}.md` and commit it yourself. I won't auto-write to rules/."
- **Decision:** Write the ADR stub to `docs/architecture/decisions/ADR-NNN-{slug}.md` (next available NNN). Instruct: "Review the stub, adjust, and commit."

### Auto-gated types (Pattern, Knowledge, Reference)

Write `draft` content to destination:

**Pattern → `~/.claude/memory/patterns.md`:**
```bash
# Create file with header if absent
if [ ! -f ~/.claude/memory/patterns.md ]; then
  echo "# Pattern Store" > ~/.claude/memory/patterns.md
  echo "" >> ~/.claude/memory/patterns.md
  echo "<!-- cap: 50 | warn-at: 40 | auto-pruned: oldest quarantine first -->" >> ~/.claude/memory/patterns.md
fi
# Append entry (newest first = prepend after header)
# Read file, insert after header line 1-3, write back
```
Prepend the draft after the file header (3 lines), so newest entries appear first.

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
Pattern fallback:  patterns.md → MEMORY.md inline with [PATTERN] prefix
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

Search patterns.md for entries with `Confidence: quarantine`:
```bash
grep -A6 "^## " ~/.claude/memory/patterns.md | grep -B3 "quarantine"
```

For each recalled pattern that **was useful** this session:
- Increment mental recall count. If pattern has been recalled ≥3 sessions: promote to `Confidence: proven` in patterns.md (Edit the file entry).

For each recalled pattern that **was harmful or misleading**:
- Change `Confidence: quarantine` to `Confidence: suspect` as a note.

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
- **Never overwrite — always append/prepend.** patterns.md and knowledge-staging.md are append-only.
- **Classify honestly.** When uncertain, prefer Pattern over Rule (lower gate = fewer blockers).
- **Ask for clarification** if the learning is ambiguous — don't guess the type.
