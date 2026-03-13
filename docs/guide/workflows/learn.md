# How Brana Learns

Brana learns from every session and applies those learnings in future work.

## The learning loop

```
Work -> Corrections/Discoveries -> Pattern Storage -> Recall -> Better Work
```

### Automatic learning (every session)

- **On correction** -- pattern captured in auto memory immediately
- **On session start** -- `session-start.sh` recalls patterns from ruflo and auto memory
- **On session end** -- `session-end.sh` computes flywheel metrics; `/brana:close` extracts and stores learnings
- **On failure** -- stop, reassess from scratch, don't patch forward

### Explicit learning

```
/brana:retrospective                    -- store a learning or pattern manually
/brana:memory recall [query]            -- search for relevant patterns
/brana:memory pollinate [query]         -- cross-client pattern transfer
/brana:memory review                    -- monthly knowledge health audit
/brana:memory review --audit [doc]      -- cross-doc contradiction detection
```

## Confidence levels

Not all memories are equal:

| Level | Confidence | Meaning |
|-------|-----------|---------|
| **Suspect** | < 0.2 | Previously demoted, treat with extreme caution |
| **Quarantined** | 0.2 - 0.7 | New or unproven, needs validation |
| **Proven** | >= 0.7 | Validated across 3+ sessions |

New learnings start at 0.5 (quarantined). Promotion happens when a pattern reaches 3+ recalls or `correction_weight >= 2` -- bumps to 0.8 confidence and transferable status.

## Cross-project transfer

Patterns marked as `transferable` can surface in other clients:

```
/brana:memory pollinate auth patterns   -- find auth patterns from other clients
```

The memory-curator agent auto-fires when starting work on a familiar problem, searching both ruflo and native auto memory.

## Storage

| Layer | What it stores | When |
|-------|---------------|------|
| **ruflo** | Semantic-searchable patterns across all clients | Primary (when available) |
| **Auto memory** | `~/.claude/projects/*/memory/MEMORY.md` | Always (fallback when ruflo unavailable) |
| **Session JSONL** | Raw tool events during a session | Temp -- consumed by `session-end.sh` |

Both layers work. ruflo adds cross-client neural search and BM25 hybrid matching.
