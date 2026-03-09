# Feature: Event Log

**Date:** 2026-03-07
**Status:** building
**Task:** t-208
**ADR:** [ADR-013](../decisions/ADR-013-event-log.md)

## Goal

A single command (`/brana:log`) to capture any event — links, calls, meetings, ideas, observations — into a searchable, append-only markdown file. Includes bulk mode for WhatsApp dumps and URL-to-task promotion.

## Audience

Anyone using brana. The log is the lowest-friction entry point into the system — no need to know tasks.json schema, pipeline stages, or memory conventions. Just `/brana:log "something happened"`.

## Constraints

- Single file (`~/.claude/memory/event-log.md`), not per-project files
- Tags for scope routing, not CWD detection
- No entry type auto-detection — inline #tags only
- URL task creation requires confirmation (AskUserQuestion)
- Append-only, chronological order within each day
- Archival at 500 lines (entries >90 days old)

## Scope (v1)

- Quick append: `/brana:log "text"` with optional `#tags`
- Bulk mode: `/brana:log bulk` → paste multi-line content → parse, deduplicate, confirm
- URL deduplication against existing research tasks
- URL-to-task creation with confirmation
- Auto-timestamping (HH:MM)
- Day headers (## YYYY-MM-DD)
- Tag extraction from inline #hashtags

## Deferred (v1.1)

- `/brana:log review` — show last 7 days, promote entries to tasks
- `/brana:log search` — cross-file keyword search (grep works for v1)
- Integration with /session-handoff (auto-prompt "anything to log?")

## Design

See [ADR-013](../decisions/ADR-013-event-log.md). Single file, tags, confirm URLs, chronological append.

### How /brana:log fits in the brana workflow

```
Something happens (call, link, idea, meeting)
        |
        v
    /brana:log "text" #tag          <-- CAPTURE (this feature)
        |
        v
  ~/.claude/memory/event-log.md
        |
        +---> URL detected? ---> confirm ---> /brana:tasks add (research stream)
        |
        +---> Actionable? ---> /brana:tasks add (manually, or via /brana:log review v1.1)
        |
        +---> Pipeline lead? ---> /brana:pipeline (manually)
        |
        +---> Pattern/learning? ---> /brana:retrospective (manually)
        |
        +---> Just context ---> stays in log (searchable via grep)
```

The log is the **inbox**. Other commands are the **outbox**. Capture fast, route later.

### Relationship to other commands

| Command | What it stores | When to use instead of /brana:log |
|---------|---------------|----------------------------|
| `/brana:tasks add` | Commitments with priority, effort, status | When you know it's actionable right now |
| `/brana:pipeline` | Leads/deals with stages and follow-ups | When you've qualified a lead |
| `/brana:retrospective` | Patterns with confidence scores | When you've confirmed a reusable learning |
| MEMORY.md | Cross-session operational facts | When it's a stable fact, not a one-time event |
| `/debrief` | Session errata and process findings | At session end (automated extraction) |
| **`/brana:log`** | **Raw events — anything that happened** | **When you just want to capture it quickly** |

## Challenger findings (incorporated)

- C1: Overlap risk — mitigated by clear "inbox vs outbox" framing. Log captures, other commands process.
- C2: CWD routing dropped — tags instead. No ambiguity.
- W1: URL auto-create dropped — confirmation required.
- W2: Entry type detection dropped — #tags only.
- W3: Skill sprawl acknowledged — /brana:log is justified because capture ≠ task management. Different semantics.
- O1: Chronological (bottom) instead of reverse — cleaner diffs.
- O2: 500-line archival added.

## Open questions

- Should `/brana:log review` auto-run at session start? (decide when building v1.1)
- Should the backup script include event-log.md? (yes — add to backup-knowledge.sh)
