# Unified Session State

> Brainstormed 2026-03-31. Status: **implemented** (t-794 phase, commits 928a598..679e28f).

## Problem

Session continuity data is trapped in a human-readable markdown file (`session-handoff.md`) that machines must regex-parse. The close skill (LLM) writes free-form markdown with headings like `**Next:**`, but the LLM paraphrases headings (e.g., `**Next -- Wave Plan (tech-debt/bugs/docs/maintenance):**`), breaking the sed/grep parser in session-start.sh. Additionally, `.needs-backprop` is a separate flag file with its own format. No shared contract exists between writer (close), parser (session-start), and reader (sitrep).

## Proposed Solution

Replace `session-handoff.md` + `.needs-backprop` with two structured JSON files:

- **`session-state.json`** -- latest session state (overwritten atomically by close via CLI)
- **`session-history.jsonl`** -- append-only archive of all past session states

The LLM never writes files directly. Close builds a JSON object, writes it to a temp file, and calls `brana session write --file /tmp/session-XXXX.json`. The Rust CLI validates the schema (serde struct), handles atomic writes, appends to history, rotates old entries, and syncs to ruflo (when available).

All programmatic consumers read structured JSON via CLI -- zero regex parsing anywhere.

### Schema (v1)

```json
{
  "version": 1,
  "written_at": "2026-03-31T20:15:00Z",
  "branch": "feat/t-793-handoff-contract",
  "session_label": "handoff format contract fix",
  "consumed_at": null,
  "accomplished": [
    "Fixed pre-tool-use hook nested path matching (t-543)",
    "Added --limit N + filter flags to backlog next (t-527)"
  ],
  "learnings": [
    "Bash ((var++)) returns exit 1 when var=0 under set -e"
  ],
  "next": [
    { "text": "Fix session continuity", "task_id": "t-614", "category": "follow-up" },
    { "text": "Run /brana:maintain-specs", "task_id": null, "category": "maintenance" }
  ],
  "blockers": [
    { "text": "Waiting on CC #24529", "task_id": "t-235" }
  ],
  "backprop": {
    "needed": true,
    "files": ["system/hooks/tdd-gate.sh", "system/hooks/hooks.json"]
  },
  "doc_drift": {
    "detected": true,
    "stale_docs": ["docs/reference/hooks.md"]
  },
  "state": {
    "key_files": ["hooks/tdd-gate.sh", "cli/backlog.rs"],
    "test_status": { "passing": 145, "failing": 0 }
  },
  "metrics": {
    "events": 47,
    "corrections": 2,
    "test_writes": 5,
    "correction_rate": 0.04,
    "test_write_rate": 0.11,
    "cascade_rate": 0.0,
    "delegation_count": 3
  }
}
```

Validated `next` categories (enum): `follow-up`, `maintenance`, `suggestion`.

`metrics` field is populated from session JSONL telemetry (`/tmp/brana-session-{SESSION_ID}.jsonl`). session-end.sh already computes these (lines 42-112). Close/session-end should include them when calling `brana session write`.

### Architecture

```
CLOSE (skill)
  |
  +-- Write JSON to temp file
  +-- brana session write --file /tmp/session-XXXX.json
  |     +-- Validate schema (serde struct)
  |     +-- Auto-fill: written_at, branch, consumed_at: null
  |     +-- Read current state -> append to history.jsonl
  |     +-- Rotate history (drop >30 days)
  |     +-- Atomic write (.tmp -> rename)
  |     +-- Sync to ruflo (if available, async, non-blocking)
  |
  v
session-state.json          <-- latest (overwritten each close)
session-history.jsonl       <-- archive (append-only, rotated)
  |
  +-- SESSION-START.SH reads via: brana session read --json
  |     +-- Returns structured fields (no jq dependency)
  |     +-- Sets consumed_at (optimistic write-first)
  |     +-- Falls back to session-handoff.md during migration
  |
  +-- SITREP reads via: brana session read
  |     +-- Returns human-readable text rendered from JSON
  |
  +-- SESSION-END.SH (safety net): brana session write --minimal
  |     +-- Auto-captures branch + timestamp if close didn't run
  |
  +-- brana handoff last/list/path -> aliased to brana session read/history/path
```

### CLI Commands

| Command | Purpose |
|---------|---------|
| `brana session write --file <path>` | Validate + write state + archive + ruflo sync |
| `brana session write --minimal` | Auto-capture (session-end.sh safety net) |
| `brana session read [--json]` | Read latest state. Default: human text. `--json`: raw |
| `brana session history [--limit N]` | List past sessions from JSONL |
| `brana session migrate` | One-time: parse session-handoff.md -> bootstrap JSON |
| `brana session path` | Return session-state.json path |

Backward compat: `brana handoff last/list/path` become aliases.

### File Ecosystem (final)

| File | Status | Writer | Reader |
|------|--------|--------|--------|
| `session-state.json` | NEW | close (via CLI) | session-start, sitrep (via CLI) |
| `session-history.jsonl` | NEW | close (via CLI, append) | `brana session history` |
| `session-handoff.md` | DEPRECATED (read-only archive) | -- | migration fallback only |
| `.needs-backprop` | KILLED | -- | absorbed into backprop field |
| `MEMORY.md` | unchanged | close | session-start |
| `memory/*.md` | unchanged | close | session-start |
| `cc-changelog-report.md` | unchanged (separate writer) | scheduler | session-start |
| `tasks.json` | unchanged | close, build | session-start, sitrep |
| ruflo memory | SYNC TARGET | close (via CLI) | semantic search |

### Consumer Changes

| Consumer | Before | After |
|----------|--------|-------|
| close (Step 9) | Write markdown to session-handoff.md | Build JSON, write temp file, `brana session write --file` |
| close (Step 8) | Write .needs-backprop flag file | Write `backprop` field in JSON |
| session-start.sh | sed/grep regex on markdown | `brana session read --json` (Rust, no jq) |
| sitrep | LLM reads raw markdown | `brana session read` (rendered text from JSON) |
| session-end.sh | Write minimal markdown | `brana session write --minimal` |
| brana handoff last | Return raw markdown | Alias to `brana session read` |
| brana handoff list | Parse `## ` headings | Alias to `brana session history` |

## Research Findings

- **Existing CLI patterns:** serde derive structs, anyhow::Result, atomic writes (.tmp -> rename). No external validator crate. Established across inbox, feed, files subsystems.
- **Transport evaluation:** File JSON is optimal for ~2 ops/session. Ruflo sync adds semantic search. Redis/HTTP/SQLite add complexity without matching the access pattern.
- **Concurrent worktrees:** Single file with last-write-wins is safe because close is a terminal event. consumed_at tracks whether session-start loaded the state.

## Risks

| Risk | Mitigation |
|------|-----------|
| LLM builds malformed JSON | Write to temp file (no shell escaping). CLI validates. On failure: minimal stub. |
| consumed_at crash mid-read | Write consumed_at first (optimistic). Crash = next session gets nothing (safe). |
| jq dependency on critical path | Use `brana session read --json` (Rust CLI). Zero jq on critical path. |
| 16 existing session-handoff.md files | `brana session migrate` bootstraps JSON. Fallback to .md during transition. |
| History grows unbounded | `brana session write` rotates >30 days as part of write. |
| session-end.sh safety net | `brana session write --minimal` captures branch + timestamp. |

## Key Design Decisions

1. **Enforce at the CLI, not the LLM.** The LLM builds data; the CLI validates and writes. This eliminates the root cause (LLM paraphrasing breaks format).
2. **File primary + ruflo sync.** Offline-first. JSON files are source of truth. Ruflo gets a copy for semantic search when available.
3. **Single session-state.json, last-write-wins.** Concurrent worktree sessions are safe because close is terminal. consumed_at tracks load status.
4. **session-handoff.md deprecated, not deleted.** Kept as read-only archive. Migration command bootstraps JSON from existing entries.
5. **Temp file for LLM -> CLI handoff.** `--file /tmp/session.json` eliminates shell quoting/escaping issues vs `--json '{...}'`.

## Next Steps

1. Define Rust structs (SessionState, NextItem, Backprop, etc.) with serde derive
2. Implement `brana session write` (validate, archive, atomic write, ruflo sync)
3. Implement `brana session read` (read JSON, render text or raw)
4. Implement `brana session history` (read JSONL, list entries)
5. Implement `brana session migrate` (parse .md -> write JSON)
6. Update close SKILL.md (Step 8+9 -> build JSON, write temp file, call CLI)
7. Update session-start.sh (-> `brana session read --json`, set consumed_at)
8. Update sitrep SKILL.md (reference structured data)
9. Update session-end.sh (call `brana session write --minimal`)
10. Add ruflo sync to write path (async, non-blocking, graceful degradation)
11. Alias `brana handoff` -> `brana session` commands
