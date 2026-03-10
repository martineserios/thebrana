# Capturing Events

The `/brana:log` command is the lowest-friction way to record anything that happens -- calls, meetings, ideas, links, observations.

## Quick start

```
/brana:log "Call with Juan from Kapso -- interested in automation #somos #call"
/brana:log bulk                    -- paste a WhatsApp dump or meeting notes
```

## How it works

- Events go to a single file: `~/.claude/memory/event-log.md`
- Organized by date, timestamped, tag-indexed
- URLs are auto-detected -- brana asks if you want to create research tasks from them
- Duplicate detection prevents logging the same thing twice
- Entries older than 90 days are auto-archived when the file exceeds 500 lines

## Tags

Add `#tags` inline -- they serve as the filtering mechanism:

```
/brana:log "Found an article on RAG patterns #research #knowledge-graphs"
/brana:log "Competitor launched new pricing #tinyhomes #competitive"
```

## Bulk mode

For multi-line content like WhatsApp dumps or meeting notes:

```
/brana:log bulk
```

Parses WhatsApp message format, deduplicates entries, and appends structured log entries.

## What /brana:log is NOT

| /brana:log | Use instead |
|-----------|-------------|
| Not a task tracker | `/brana:backlog add` -- tasks are commitments |
| Not a pattern store | MEMORY.md -- stores reusable patterns |
| Not a deal tracker | `/brana:pipeline` -- tracks deals through stages |

The log is an **inbox**. Other commands are the **outbox**. Capture fast, route later.
