# Session Continuity — Multi-Session & Cross-Project

> Brainstormed 2026-05-19. Updated 2026-05-25. Status: in-progress (Fix A shipped 2026-05-19; Fix B → t-1461; Fix C — initiative accumulator → backlogged).
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

### Fix C — Initiative-aware session continuity (Rust + procedures)

Multi-session work on the same initiative loses its cross-day arc because `session-state.json` is ephemeral (daily TTL). The solution is a three-tier persistence model:

```
session-state.json               → daily TTL (today only, replaced tomorrow)
session-initiatives/{slug}.json  → initiative TTL (survives until initiative ships)
session-history.jsonl            → all-time log (never pruned)
```

#### Data flow

```
close (each session)
  ├── writes session-state.json      (daily, ephemeral)
  ├── appends session-history.jsonl  (all-time log)
  └── upserts session-initiatives/X.json  (cross-day accumulator)

sitrep (next session start)
  ├── reads session-initiatives/X.json → initiative progress view
  └── reads session-state.json        → general pending items
```

#### Initiative detection at close (3-tier cascade)

> Challenger-reviewed 2026-05-25. Tier 1 scoped together with this task (not a separate enhancement).

1. **Tier 1 (auto):** `brana backlog start t-NNN` writes `initiative` to a session-start marker → close reads it silently. **Scoped in this task** — `backlog start` must be modified in the same PR.
2. **Tier 2 (auto — 3 signals in parallel):** No marker → run all three simultaneously:
   - **2a.** `brana backlog query --status in_progress` → collect `initiative` fields from active tasks *(strongest signal — no commits required)*
   - **2b.** `git log` → task IDs in commit messages → look up `initiative` field on those tasks
   - **2c.** Branch name parsing (`feat/gemini-orchestration` → `"gemini-orchestration"`)
   
   Converge: union all detected initiatives, dedup. Exactly 1 unique → use it silently.
3. **Tier 3 (prompt):** 0 or 2+ unique initiatives → one `AskUserQuestion` at close. User skips → no initiative file touched, session goes to general history only.

#### File layout

> Challenger flag: second write path must mirror SessionState guards exactly.

```
brana-core/src/
  session.rs                — SessionState, write_state() — unchanged
  session_initiative.rs     — InitiativeAccumulator, upsert_initiative(), archive()
  session_common.rs         — shared write_atomic(), validate trait (extracted from session.rs)
```

`#[serde(default)]` required on **all fields** of `InitiativeAccumulator`. `validate()` required before any write. Atomic write via `session_common::write_atomic()` — same path as `write_state()`.

#### Initiative accumulator — merge-on-write mechanics

Each close does **read → merge → atomic write** on `session-initiatives/{slug}.json`:

| Field | Merge rule | Dedup key |
|---|---|---|
| `accomplished[]` | append new items | task_id or normalized text |
| `next[]` | append new + prune (see below) | task_id |
| `resolved[]` | append pruned items with note | task_id or text |
| `learnings[]` | append new | first 60 chars |
| `tasks_completed[]` | append new IDs | task_id |
| `sessions_count` | `+= 1` | — |
| `last_closed` | overwrite | — |

**`next[]` pruning — two passes, LLM-mediated:**

- **Pass 1 (task_id-linked):** Query backlog status at merge time. `completed` or `cancelled` → move to `resolved[]`.
- **Pass 2 (text-only, task_id: None):** At close time, Claude reviews each text-only `next[]` item against the session's `accomplished[]` + git log. Items addressed → move to `resolved[]` with a one-line resolution note. Items not addressed → carry forward.

No TTL. No text matching. The system closes the loop it opened because it has full session context.

**`resolved[]` item shape:**
```json
{
  "text": "Add regression tests for Watch + serde(default)",
  "task_id": null,
  "resolved_at": "2026-05-26",
  "resolved_by": "session-close",
  "resolution": "Tests written this session — commit 94dc7b2"
}
```

#### Schema addition to `SessionState`

`initiative: Option<String>` — populated by close when Tier 1/2/3 detection succeeds. `#[serde(default)]` required. Sitrep reads it to know which initiative file to load.

#### Parallel session safety

Both terminals close on the same initiative → both upsert `session-initiatives/X.json` (read→merge→write). Close is interactive so true concurrent writes are rare. If they happen: last-write-wins — one session's items may be missed (recoverable from `session-history.jsonl`). File locking deferred.

#### Initiative lifecycle

- **Active:** accumulator grows on each close where initiative is detected
- **Shipped (v1):** When sitrep detects 100% tasks completed, close offers: "Archive initiative?" → `mv session-initiatives/X.json session-initiatives/archive/X-{date}.json`. Sitrep stops surfacing it.
- **Shipped (future):** `brana backlog complete --initiative X` CLI command — separate follow-up task.

#### Effort: L (blocked_by t-1461 — same-day merge is schema prerequisite)

---

## Next steps

1. ✅ Fix A: Edit `close.md` + `sitrep.md` — shipped 2026-05-19
2. t-1461: Fix B — same-day merge semantics (Rust) — backlogged
3. t-1462: Cross-project daily view (`brana session today`) — backlogged, blocked_by t-1461
4. Fix C: Initiative accumulator — backlogged, blocked_by t-1461 (schema prerequisite)

## Engineering disciplines

- **DDD:** ADR needed before Fix B + Fix C (schema changes to `SessionState`, new file layout)
- **TDD:** Tests for merge/replace logic (Fix B) + upsert/dedup/prune logic (Fix C) before Rust
- **SDD:** Update `docs/architecture/session.md` (or create) after implementation
- **Docs:** Update `sitrep.md` + `close.md` procedures in same commit as implementation
