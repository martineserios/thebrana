# How Brana Learns

Brana learns from every session and applies those learnings in future work.

## The learning loop

```
Work → Corrections/Discoveries → Pattern Storage → Recall → Better Work
```

### Automatic learning (every session)

- **On correction** — pattern captured in auto memory immediately
- **On session start** — patterns recalled and applied
- **On session end** — `/brana:close` extracts and stores learnings
- **On failure** — stop, reassess, don't patch forward

### Explicit learning

```
/brana:retrospective         — store a learning or pattern manually
/brana:memory recall [query] — search for relevant patterns
/brana:memory pollinate      — cross-client pattern transfer
/brana:memory review         — monthly knowledge health audit
/brana:memory review --audit — cross-doc contradiction detection
```

## Confidence levels

Not all memories are equal:

| Level | Confidence | Meaning |
|-------|-----------|---------|
| **Suspect** | < 0.2 | Previously demoted, treat with extreme caution |
| **Quarantined** | 0.2 - 0.7 | New or unproven, needs validation |
| **Proven** | >= 0.7 | Validated across 3+ sessions |

New learnings start at 0.5 (quarantined). They get promoted through recall and confirmation.

## Cross-project transfer

Patterns marked as `transferable` can surface in other clients:

```
/brana:memory pollinate      — find patterns from other clients relevant to current work
```

## Storage

- **claude-flow** — semantic search across all clients (primary)
- **Auto memory** — `~/.claude/projects/*/memory/MEMORY.md` (fallback)
- Both work — claude-flow adds cross-client neural search
