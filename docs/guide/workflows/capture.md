# Capturing Events

The `/log` command is the lowest-friction way to record anything that happens — calls, meetings, ideas, links, observations.

## Quick start

```
/log "Call with Juan from Kapso — interested in automation #somos #call"
/log bulk                    — paste a WhatsApp dump or meeting notes
```

## How it works

- Events go to a single file: `~/.claude/memory/event-log.md`
- Organized by date, timestamped, tag-indexed
- URLs are auto-detected — brana asks if you want to create research tasks from them
- Duplicate detection prevents logging the same thing twice

## Tags

Add `#tags` inline — they're visible in the entry and serve as the filtering mechanism:

```
/log "Found an article on RAG patterns #research #knowledge-graphs"
/log "Competitor launched new pricing #tinyhomes #competitive"
```

## What /log is NOT

- Not `/tasks add` — tasks are commitments, log entries are observations
- Not MEMORY.md — memory stores patterns, log stores events
- Not `/pipeline` — pipeline tracks deals, log captures first contact

The log is an **inbox**. Other commands are the **outbox**. Capture fast, route later.
