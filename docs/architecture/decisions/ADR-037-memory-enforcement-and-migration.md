---
status: accepted
---
# ADR-037: Memory Enforcement Hook + Incremental Migration Policy

**Status:** Accepted  
**Date:** 2026-04-14  
**Task:** t-1243 (Wave 1 — t-1238 memory taxonomy)  
**Depends on:** ADR-034 (skill tiering), memory-taxonomy-sdd.md

---

## Context

Wave 0 (t-1241) ships the `/brana:retrospective` classify-then-route procedure. Without
enforcement, the old write path (`feedback_*.md` creation) can still be triggered —
either by habit, by skills not yet updated, or by direct Write tool calls.

128 existing `feedback_*.md` files must also be migrated to the taxonomy without
disrupting active sessions.

---

## Decision

### A. PreToolUse Hook — advisory gate on feedback_*.md writes

A `PreToolUse` hook watches for Write calls targeting `**/memory/feedback_*.md`.

**Wave 1 behavior (advisory):**
```
When triggered:
  Print warning to stderr — do not block the write.
  Message: "⚠ feedback_*.md creation detected. Use /brana:retrospective to route
  this correctly. Set BRANA_MEMORY_OVERRIDE=1 to suppress this warning."
  Log to ~/.claude/memory/override-log.md.
```

**Wave 2 behavior (blocking — t-1245, after 1 session cooling-off):**
```
When triggered:
  Block the write (return {"continue": false}).
  Unless BRANA_MEMORY_OVERRIDE=1 is set in environment.
```

Cooling-off condition: Wave 2 cannot start until this ADR is committed **and** at
least 1 full session has passed. Flag in backlog: t-1245 blocked_by this ADR.

### B. Incremental migration policy

Do not bulk-migrate. Existing `feedback_*.md` files are read daily — disrupting
them mid-session causes confusion.

**On-encounter rule (always):**
- When any skill reads a `feedback_*.md` file, classify its content via the taxonomy
  and write a migrated entry to the canonical destination.
- Delete or rename the original: `feedback_<name>.md` → `feedback_<name>.md.migrated`.
- Cap: ≤5 files migrated per session (avoid context saturation).

**Monthly sweep (t-1246):**
- Bulk-archive any `feedback_*.md` with no reads in the last 90 days.
- Move to `~/.claude/memory/archive/` (not deleted — human reviews before purge).
- Run via `/brana:memory review` or manually.

**Phase A triage manifest (before any bulk move):**
- A human-reviewed triage manifest listing each file's proposed destination must be
  approved before bulk migration begins (Wave 3 — t-1247+).
- No auto-migration of Layer 1 content (rules, decisions) — always human gate.

---

## Consequences

- `feedback_*.md` writes are visible to the operator via the advisory hook starting
  Wave 1. No write failures; no disruption to active skills.
- After Wave 2 (blocking), any skill still writing `feedback_*.md` without override
  will be caught — surfacing what needs to be updated next.
- Migration is incremental and reversible. `.migrated` suffix preserves originals.
- Wave 3 bulk migration requires human approval of triage manifest — no accidental
  loss of Layer 1 content.

## Non-actions

- **No scheduled migration job.** On-encounter + monthly sweep is sufficient.
- **No auto-classification of existing files in bulk.** LLM misclassification at
  scale could corrupt Layer 1 (rules) destinations. Human gate required.
- **No blocking in Wave 1.** Advisory-only until all active skills are updated.
