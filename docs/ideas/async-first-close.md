# Async-First Close + Nightly Extraction Cron

> Brainstormed 2026-06-10. Status: idea.

## Problem

`/brana:close` runs synchronously at session end — the moment attention is already gone. The FULL mode (default for any session with ≥2 commits or code file changes) runs 17 steps across 7 phase files: 5 parallel extraction agents, multiple `AskUserQuestion` gates, memory write sentinels, doc drift scans. The 80% case (standard dev session) doesn't need that depth, but FULL triggers almost every time.

The bottleneck is all of: LLM extraction rounds, phase file loading overhead, and interactive prompts that require user presence.

## Core insight: close conflates two different concerns

| Concern | Urgency | Who needs to be present |
|---------|---------|------------------------|
| Session continuity (handoff + what's next) | High — needed at next session start | Nobody — template-fill |
| Learning extraction (errata, patterns, field-notes) | Low — can be deferred 1 session | Nobody — LLM worker |
| System maintenance (drift, worktrees, stash) | Low — can be deferred | Nobody |

All three run synchronously today. None of them need you there.

## Proposed solution: Async-first close

### Architecture

```
close (30s)          nightly cron (2am)         session start
─────────────        ────────────────────        ─────────────
snapshot git diff → process queue entries    → "Yesterday: 2 patterns,
write handoff      → run 1 LLM pass/session     1 errata filed."
queue entry        → route patterns/errata
done               → write daily-summary.md
                   → clear queue
```

### Track 1 — Close-instant (default, 30 seconds)

1. `git diff HEAD~N..HEAD` → save to `~/.claude/sessions/close-snap-{branch}-{date}.diff`
2. Template-fill handoff: branch + in-flight tasks + last 5 commits (no LLM)
3. Append to `close-queue.json`:
   ```json
   {
     "timestamp": "2026-06-10T23:15:00Z",
     "branch": "feat/t-1234-feature",
     "snapshot_path": "~/.claude/sessions/close-snap-20260610.diff",
     "git_range": "abc123..def456",
     "project": "thebrana",
     "processed": false
   }
   ```
4. Print: "Closed. [N sessions queued for tonight's extraction]"

### Track 2 — Nightly extraction cron (2am daily, via `brana:scheduler`)

1. Read `close-queue.json` for unprocessed entries
2. For each snapshot: single LLM pass over saved diff → extract errata/patterns/field-notes
3. Route extracted learnings:
   - Errata → append to errata doc
   - Patterns (SMALL) → auto-store to ruflo/memory
   - Patterns (LARGE/novel) → write to reminder queue (see below)
4. Write `~/.claude/sessions/daily-summary-{date}.md`
5. Mark entries `processed: true`

### Track 3 — Full debrief (explicit, `/brana:close --full`)

Current FULL close behavior. Reserved for milestones, releases, or manual deep debrief.

### Session start

If daily summary exists → surfaced in startup context (already wired to session-start hook).
Large patterns pending routing → shown as reminders (see Reminder system below).

## Reminder system (brana CLI extension + hook integration)

The reminder system has two layers: (1) **event-based** — hooks write reminders in real-time when conditions match; (2) **batch-based** — nightly cron writes reminders for large/novel patterns pending human routing. Both write to the same `~/.claude/reminders.json` store.

A shell helper (`system/hooks/lib/remind.sh`) lets any hook write a reminder in one line — no hook needs to know about the store format. This makes the reminder system trivially extensible: any new hook can add a reminder trigger without a schema migration.

The nightly extraction identifies learnings that need human review before routing (LARGE patterns, novel ADR candidates). Instead of blocking close or prompting at session start, these go into the same reminder queue.

**Proposed: `brana remind` command**

```
brana remind list              # show pending reminders
brana remind resolve <id>      # mark done / route to memory
brana remind snooze <id> 3d    # push back 3 days
```

**Reminder sources:**
- Nightly extraction: large/novel patterns pending classification
- Accumulated errata: same issue flagged across N sessions → "consider making this a rule"
- Deferred doc updates: N sessions passed without updating doc flagged for drift
- Queued close snapshots unprocessed >3 days (extraction cron failed or was off)

**Integration points:**
- `brana backlog status` → add "Reminders: N pending" line if queue non-empty
- Session-start hook → show reminder count in startup context, not full list
- `/brana:sitrep` → include top 1-2 reminders in focus section

## What this preserves

- Pattern routing — same depth, 8 hours later
- Handoff continuity — instant, template-driven, always reliable
- Learnings capture — same signal, zero session overhead
- FULL debrief — available on demand via `--full`

## What changes

- Close is no longer a blocking ritual — 30-second snapshot + queue
- Extraction is a nightly concern, not session-end concern
- Interactive gates at close time: **eliminated**
- Large pattern routing: deferred to reminder system

## Risks

| Risk | Mitigation |
|------|-----------|
| Extraction worker loses conversation context (only has diff) | Diff captures what changed; conversation dynamics are lower signal than code changes |
| Cron fails silently — queue grows stale | Reminder system surfaces stale queue entries after 3 days |
| Snapshot files accumulate on disk | Cron cleans up snapshots older than 14 days after processing |
| Multiple sessions close before cron runs | Queue is append-only, cron processes all entries in one pass |

## Engineering disciplines

- **DDD:** ADR — async-first close architecture, queue schema, cron contract, reminder system design
- **TDD:** Queue append idempotency, snapshot capture, cron dispatch, extraction worker, reminder CRUD
- **SDD:** `close/SKILL.md` phase registry, `session-state.md`, `close-queue.json` schema doc

## Next steps

1. **t-1961** — Research: async close queue schema + cron contract (gates implementation)
2. **t-1963** — Research: reminder system design — schema, sources, lifecycle, surfacing points (gates t-1962)
3. ADR: async-first close architecture (decision: sync → async, queue schema, failure handling)
4. Implement Track 1 (close-instant): modify `close/SKILL.md` to default to snapshot + queue
5. Write nightly cron script (`system/cron/close-extraction.sh`) using `brana:scheduler`
6. Wire daily-summary to session-start hook
7. **t-1962** — Implement `brana remind` CLI subcommand (blocked by t-1961 + t-1963)
8. Keep `--full` as escape hatch (no changes to current FULL behavior)
