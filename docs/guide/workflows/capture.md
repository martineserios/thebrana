# Capturing Events

The `/brana:log` command is the lowest-friction way to record anything that happens — calls, meetings, ideas, links, observations.

## Quick start

```
/brana:log "Call with Juan from Kapso — interested in automation #somos #call"
/brana:log bulk                    — paste a WhatsApp dump or meeting notes
```

## How it works

- Events go to a single file: `~/.claude/memory/event-log.md`
- Organized by date, timestamped, tag-indexed
- URLs are auto-detected — brana asks if you want to create research tasks from them
- Duplicate detection prevents logging the same thing twice

## Tags

Add `#tags` inline — they're visible in the entry and serve as the filtering mechanism:

```
/brana:log "Found an article on RAG patterns #research #knowledge-graphs"
/brana:log "Competitor launched new pricing #tinyhomes #competitive"
```

## What /brana:log is NOT

- Not `/brana:tasks add` — tasks are commitments, log entries are observations
- Not MEMORY.md — memory stores patterns, log stores events
- Not `/brana:pipeline` — pipeline tracks deals, log captures first contact

The log is an **inbox**. Other commands are the **outbox**. Capture fast, route later.
