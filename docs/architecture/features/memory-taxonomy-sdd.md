# Memory Taxonomy — Solution Design

**Task:** t-1270  
**Wave:** 1 — Design record  
**Status:** superseded (taxonomy types, see ADR-038)  
**Date:** 2026-04-14  
**Depends on:** [memory-taxonomy-ddd.md](memory-taxonomy-ddd.md)  
**Superseded by:** [ADR-038](../decisions/ADR-038-memory-write-gate-and-per-pattern-files.md) — ADR-038 defines the authoritative 7-type routing table (feedback/project/user/pattern/convention/field-note/adr). This SDD's 6-type classify() interface remains a valid implementation record for the write path, but the type taxonomy and routing table are governed by ADR-038.

---

## Overview

This doc specifies how the original 6-type taxonomy (DDD) was implemented. **The type taxonomy is superseded by ADR-038's 7-type routing table** — see the Superseded by note above. The classify() interface, write path, and hook spec remain valid implementation references.

1. `classify()` — the routing function interface
2. File formats — `patterns.md`, `knowledge-staging.md`
3. Write-site integration — where classify() is called
4. Hook spec — PreToolUse gate on `feedback_*.md`
5. Cap enforcement — warn and block thresholds
6. Fallback chain — degraded operation when components are unavailable

---

## 1. classify() Interface

`classify()` is a conceptual function — implemented as a prompt step inside `/brana:close` Step 5, not as a standalone script.

### Input

```
text: string          — the raw learning or finding to be stored
source_task: string   — task ID or session context (for provenance)
```

### Output

```json
{
  "type": "rule | pattern | knowledge | decision | reference | session",
  "destination": "<canonical path or keyword>",
  "confidence": "high | medium | low",
  "draft": "<formatted content for the destination>",
  "gate": "auto | human"
}
```

### Classification algorithm

Apply the DDD decision tree in order. When a type is matched:

1. Format `draft` using that type's file format (see §2)
2. Set `gate`:
   - `rule` → `human`
   - `decision` → `human`
   - all others → `auto`
3. Return immediately — do not continue evaluating

**Tie-breaking:** If two types are plausible (e.g., a Pattern that could also be a Rule), prefer the lower-gate type — Pattern over Rule — and note the ambiguity in `draft` so the human can override.

### Confidence scoring

| Score | Meaning | Action |
|-------|---------|--------|
| high | Single type match, clear home | Write immediately (if auto-gate) |
| medium | Match found but ambiguous destination | Write with note |
| low | No clear match | Fall back to MEMORY.md inline entry; flag for review |

---

## 2. File Formats

### 2a. patterns.md

**Path:** `~/.claude/memory/patterns.md`  
**Encoding:** UTF-8 Markdown  
**Structure:** flat list of `##`-headed entries, newest first

```markdown
# Pattern Store

<!-- cap: 50 | warn-at: 40 | auto-pruned: oldest quarantine first -->

## {pattern-name-slug}

**Problem:** {one sentence — the situation that triggers this pattern}
**Solution:** {what to do, concrete enough to apply without context}
**Why:** {evidence or reasoning — a past incident, test result, or principle}
**Confidence:** quarantine | proven
**Source:** {task-id | session-date}
**Added:** {YYYY-MM-DD}
```

**Example:**

```markdown
## git-worktree-untracked-files

**Problem:** `git checkout -b` blocked by worktree-gate when untracked files exist; `git stash` also fails because stash pop re-triggers the hook.
**Solution:** Skip stash entirely. Use `git worktree add <path> <branch>` then `cp <untracked-files> <worktree-path>/`.
**Why:** Worktree-gate fires on checkout, not on worktree add. Untracked files transfer cleanly via cp.
**Confidence:** proven
**Source:** t-500
**Added:** 2026-03-15
```

**Pruning rule:** When count reaches cap (50), delete the oldest entries with `confidence: quarantine`. Never auto-delete `proven` entries.

---

### 2b. knowledge-staging.md

**Path:** `~/.claude/memory/knowledge-staging.md`  
**Encoding:** UTF-8 Markdown  
**Structure:** flat list of `##`-headed entries, newest first

```markdown
# Knowledge Staging

<!-- cap: 30 | warn-at: 20 | stale-after: 30 days -->

## {topic-slug}

**Claim:** {the knowledge — a fact, model, or finding}
**Source:** {doc, session, or external ref}
**Confidence:** low | medium | high
**Added:** {YYYY-MM-DD}
**Promote to:** {path/to/dimension-doc.md | portfolio.md | MEMORY.md}
**Promoted:** {YYYY-MM-DD | —}
```

**Example:**

```markdown
## gemini-is-detail-extraction

**Claim:** Gemini in NotebookLM is a detail-extraction engine, not a synthesis engine. Broad system names + abstract framing triggers canned responses. Fix: lead with specific tool/hook names, use enumeration framing, include anti-hallucination instruction.
**Source:** session 2026-04-01, NotebookLM experiments
**Confidence:** high
**Added:** 2026-04-01
**Promote to:** brana-knowledge/dimensions/notebooklm.md
**Promoted:** —
```

**Stale detection:** Entries with `Promoted: —` and `Added` >30 days ago are stale. `/brana:memory review` surfaces them.

---

## 3. Write-Site Integration

Every write site that currently outputs `feedback_*.md` must call `classify()` instead.

### 3a. /brana:close Step 5 (primary write site)

Current behavior:
```
For each learning/pattern identified:
  → write ~/.claude/projects/{slug}/memory/feedback_{name}.md
  → add pointer to MEMORY.md
```

New behavior:
```
For each learning/pattern identified:
  result = classify(text, source_task)

  if result.gate == "human":
    AskUserQuestion:
      question: "Classify as {result.type}?"
      header: "Memory routing"
      options:
        - "Yes — {result.type} → {result.destination}"
        - "Override type: Rule"
        - "Override type: Pattern"
        - "Skip"
    → write to destination on approval

  if result.gate == "auto":
    → write result.draft to result.destination
    → log to MEMORY.md only if type is Reference or high-value Pattern
      (Patterns are indexed via patterns.md; no MEMORY.md entry needed per-pattern)
```

### 3b. /brana:retrospective (secondary write site)

Currently writes `feedback_*.md` directly. After taxonomy:
```
classify(text, source_task)
→ same routing as close Step 5
→ no feedback_*.md output
```

### 3c. Session-end-persist.sh (session state write site)

No change. Session state is always type 6 (Session). No classify() call needed. Writes directly to native memory dir JSON.

---

## 4. PreToolUse Hook Spec

A lightweight advisory hook prevents new `feedback_*.md` files from being created outside the sanctioned write sites.

### Trigger

```json
{
  "event": "PreToolUse",
  "matcher": {
    "tool": "Write",
    "file_path_glob": "**/memory/feedback_*.md"
  }
}
```

### Behavior (advisory, not blocking — Wave 2 makes it blocking)

When triggered:
```
Print to stderr:
  "⚠ feedback_*.md creation detected. The memory taxonomy (t-1238) routes
   learnings by type — Rule/Pattern/Knowledge/Decision/Reference/Session.
   Use /brana:close or /brana:retrospective to store this correctly.
   To override: set BRANA_MEMORY_OVERRIDE=1 in your shell."
```

If `BRANA_MEMORY_OVERRIDE=1` is set: allow write, log override to `~/.claude/memory/override-log.md`.

**Promotion to blocking** happens in t-1245 (Wave 2) after the write sites are updated and the team has confirmed no legitimate `feedback_*.md` writes remain.

---

## 5. Cap Enforcement

Cap enforcement runs inside `/brana:close` and `/brana:retrospective` before writing.

### patterns.md caps

| Threshold | Action |
|-----------|--------|
| ≥40 entries | Warn: "patterns.md at {N}/50. Consider promoting proven patterns to dimension docs." |
| =50 entries | Block write. Require pruning first: show oldest 5 quarantine entries, offer deletion. |

### knowledge-staging.md caps

| Threshold | Action |
|-----------|--------|
| ≥20 entries | Warn: "knowledge-staging.md at {N}/30. Run `/brana:memory review` to promote stale entries." |
| =30 entries | Block write. Require promotion or deletion of ≥1 entry first. |

### MEMORY.md line budget

| Threshold | Action |
|-----------|--------|
| ≥180 lines | Warn at close time: "MEMORY.md at {N}/200 lines." |
| ≥195 lines | Hard block: no new MEMORY.md entries until trimmed. |

---

## 6. Fallback Chain

When a destination is unavailable, degrade gracefully:

```
Primary destination unavailable?
  → Try next in chain
  → Log fallback to ~/.claude/memory/fallback-log.md

Chain per type:
  Rule:       system/rules/ → MEMORY.md inline [human-gated, no auto-fallback]
  Pattern:    patterns.md → MEMORY.md inline (with [PATTERN] prefix)
  Knowledge:  knowledge-staging.md → MEMORY.md inline (with [KNOWLEDGE] prefix)
  Decision:   ADR stub → docs/architecture/decisions/ → MEMORY.md inline [human-gated]
  Reference:  portfolio.md → MEMORY.md inline
  Session:    native memory JSON → MEMORY.md inline (last resort only)
```

**Ruflo down:** All types work without ruflo. `patterns.md` is the canonical Pattern store; ruflo indexes on top as enhancement. If ruflo is down, `/brana:memory recall` falls back to grepping `patterns.md` + `knowledge-staging.md`.

---

## 7. Interfaces with Other Skills

| Skill / Script | Change |
|----------------|--------|
| `/brana:close` | Step 5 calls classify(); Steps 5b/6 updated routing table |
| `/brana:retrospective` | Replaces direct feedback_*.md write with classify() |
| `/brana:memory` | `recall` subcommand searches patterns.md + knowledge-staging.md + MEMORY.md |
| `/brana:memory review` | Surfaces stale knowledge-staging entries + cap warnings |
| `/brana:research` | Accepts knowledge-staging.md entries as promotion candidates |
| `session-end-persist.sh` | No change (Session type, direct write) |
| `lint-heal.sh` | Extended to validate patterns.md + knowledge-staging.md format |
| `index-patterns.sh` | Extended to index patterns.md alongside ruflo memory_entries |

---

## Open Questions → Resolved

| Question (from DDD) | Resolution |
|---------------------|------------|
| Who enforces Pattern cap? | `/brana:close` reads count before writing. No scheduled job needed. |
| Knowledge promotion trigger? | `/brana:close` offers inline promotion if entry is ≥14 days old and confidence=high. Otherwise `/brana:research --refresh` handles batch promotion. |
| Existing feedback_*.md migration? | Wave 3 (t-1247–t-1261). Phase A triage manifest approved by human before any move. No auto-migration. |
