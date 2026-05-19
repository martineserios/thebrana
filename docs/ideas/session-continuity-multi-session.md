# Session Continuity — Multi-Session & Cross-Project

> Brainstormed 2026-05-19. Status: in-progress (Fix A shipped 2026-05-19; Fix B → t-1461; cross-project → t-1462).
> Related: [`unified-session-state.md`](./unified-session-state.md) (implemented t-794), [`session-memory-cc-alignment.md`](./session-memory-cc-alignment.md) (shape only)

## Problem

Two distinct but related gaps in the close/sitrep loop that cause items to fall through the cracks across sessions:

### Gap 1 — Parallel session replacement

`brana session write` always replaces `session-state.json` unconditionally. When two sessions close on the same project on the same day, the second close overwrites the first's `accomplished`, `next`, and `learnings`. The `session-history.jsonl` archive captures both entries, but nothing reads it for continuity — sitrep only reads the latest `session-state.json`.

User context: parallel CC sessions daily (multiple terminals per project + switching between projects throughout the day).

### Gap 2 — Close-to-sitrep pipeline gaps

Items written by `/brana:close` fall through at four specific points before reaching `/brana:sitrep`:

| Step | What breaks | Impact |
|------|------------|--------|
| Step 3b (doc skip) | User chooses "Skip" → doc-update reminder dropped entirely | Deferred doc updates never surface next session |
| Step 4 (errata) | E{ID} written to errata doc, no `next[]` entry created | No reconcile reminder at next sitrep |
| Step 8 (drift) | `doc_drift.stale_docs` written to session JSON, not to `next[]` | Sitrep never reads `doc_drift` field directly |
| Step 12 (tasks skipped) | Follow-ups offered, user skips, items evaporate | Actionable items permanently lost |

## Proposed solution

### Fix A — Procedure changes (close.md + sitrep.md) — no Rust

**close.md:**
1. **Step 3b**: "Skip" writes `{text: "Doc update deferred: {file}→{target}", category: "maintenance"}` to `next[]` (currently silent)
2. **Step 4**: After writing any E{ID}, auto-insert `{text: "Run /brana:reconcile --scope propagation (errata {IDs})", category: "maintenance"}` into `next[]`
3. **Step 8**: When `doc_drift.stale_docs` non-empty, auto-insert stale-docs reminder into `next[]`
4. **Step 12**: After AskUserQuestion for task creation, all unchosen items still land in `next[]` with `task_id: null`

**sitrep.md:**
- Source 4 extension: after reading `next[]`, also surface `backprop.needed`, `doc_drift.stale_docs`, `state.test_status.failing > 0` directly from session JSON (belt-and-suspenders fallback)

**Effort:** ~1.5h procedure edits, zero Rust.

### Fix B — Same-day merge semantics (Rust) — tracked as t-NNN

`brana session write` reads existing `session-state.json` before writing:
- Same day as `written_at` → **merge mode**: append arrays (accomplished/next/learnings/blockers), dedup by content, accumulate `session_labels: []` breadcrumb
- Different day → **replace mode** (current behavior, unchanged)

Backward-compat: `session_labels` field is optional; old entries without it are treated as `session_labels: [session_label]`.

**Effort:** ~3h Rust + tests.

### Feature — Cross-project daily view — tracked as t-NNN

`brana session today` (new CLI subcommand): scan all `~/.claude/projects/*/memory/session-state.json`, filter for today's date, aggregate accomplished/next/blockers across all projects. `/brana:sitrep --all` would call it.

**Effort:** ~2-3h Rust + procedure update.

## Next steps

1. ✅ Fix A: Edit `close.md` + `sitrep.md` — shipped 2026-05-19
2. t-1461: Fix B — same-day merge semantics (Rust) — backlogged
3. t-1462: Cross-project daily view (`brana session today`) — backlogged, blocked_by t-1461

## Engineering disciplines

- **DDD:** ADR needed before Fix B (schema change to `SessionState` struct)
- **TDD:** Tests for merge/replace logic before Rust implementation
- **SDD:** Update `docs/architecture/session.md` (or create) after implementation
- **Docs:** Update sitrep.md + close.md procedures in same commit as implementation
