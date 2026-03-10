# Research

The `/brana:research` command is the research primitive -- takes a topic, follows references recursively, produces structured findings. Runs in a forked context to preserve the main conversation.

## Quick start

```
/brana:research context engineering       -- research a topic
/brana:research 14                        -- research updates for a specific doc
/brana:research creator:simon-willison    -- check a creator's recent output
/brana:research leads                     -- process queued research leads
/brana:research registry                  -- registry health report
/brana:research --refresh                 -- batch refresh all dimension docs
/brana:research --refresh high            -- refresh high-priority docs only
```

## How it works

Three-phase architecture with scout agents:

1. **Phase 1 (wide scan)** -- up to 5-8 parallel scouts search the web (metadata only, no WebFetch)
2. **Phase 2 (triage)** -- findings ranked by severity and relevance
3. **Phase 3 (deep dive)** -- up to 3 targeted scouts with WebFetch access (max 2 WebFetch calls each)

Maximum 14 scouts total across all phases.

## With NotebookLM

```
/brana:research context engineering --nlm
```

Queries NotebookLM notebooks for prior knowledge before web research. Uses specific technical nouns as query anchors to avoid generic "canned" responses.

## Batch refresh (`--refresh`)

Refreshes dimension docs in `brana-knowledge/dimensions/` by launching parallel scout agents grouped by topic. Scopes: `all`, `high`, `medium`, `low`, `venture`, or a specific doc number.

## Key rules

- Never modify dimension docs directly (research produces findings, not edits)
- Never modify the source registry directly
- No WebFetch in Phase 1 (metadata only)
- Read temp files incrementally to manage context budget

## Related skills

| Skill | How it connects |
|-------|----------------|
| `/brana:memory` | Stores research findings as patterns |
| `/brana:maintain-specs` | Propagates research updates through doc layers |
| `/brana:notebooklm-source` | Prepares findings as NotebookLM sources |

## Tips

- Always read project docs first -- web research builds on what docs decided
- Research findings are auto-stored with low confidence (0.3) and 30-day TTL
- Findings that survive into a spec get promoted to 0.6 confidence
- The source registry tracks what was checked and when -- prevents redundant work
