# Context Budget

## Thresholds

- **<55% context:** proceed normally
- **55-70% (yellow zone):** prefer summaries over full file reads, avoid loading new large files, consider delegating next steps to subagent. **Read `/tmp/brana-context-*.md`** for session context instead of re-querying memory/ruflo/handoff.
- **70-85%:** `/compact` before the next expensive operation
- **>85%:** delegate to a fresh subagent, don't attempt in main context

Context rot is a gradient, not a cliff. Earlier intervention = better output.

## Expensive operations

- WebFetch: 50-100K tokens/call. Prefer WebSearch (~1K). Metadata-first.
- 5+ file edits: write a Python script (`/tmp/bulk-edit.py`) instead of individual Read+Edit.
- Scouts: write to temp files, return 2-line summaries. Read temp files one at a time.
- MCP servers: 4-17K tokens each. Prefer skills or sub-agents.

```
Example — at 62% (yellow zone):
  WRONG: Read 800-line file to find one setting → RIGHT: Grep, read 20 lines
  WRONG: WebFetch docs page for an API sig       → RIGHT: WebSearch (1K vs 80K)
  WRONG: 3 scouts for one question                → RIGHT: 1 scout, then decide
```

## Edit precision

- Include 3+ surrounding lines in old_string for reliable matching.
- Files under 50 LOC: prefer Write over Edit.
- Sequence: Read A → Edit A → Read B → Edit B. Never batch edits without prior reads.
