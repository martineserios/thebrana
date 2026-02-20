# Context Budget

## Thresholds

- **<70% context:** proceed normally
- **70-85%:** `/compact` before the next expensive operation
- **>85%:** delegate to a fresh subagent, don't attempt in main context

## Expensive operations

- WebFetch: 50-100K tokens/call. Prefer WebSearch (~1K). Metadata-first.
- 5+ file edits: write a Python script (`/tmp/bulk-edit.py`) instead of individual Read+Edit.
- Scouts: write to temp files, return 2-line summaries. Read temp files one at a time.
- MCP servers: 4-17K tokens each. Prefer skills or sub-agents.

## Edit precision

- Include 3+ surrounding lines in old_string for reliable matching.
- Files under 50 LOC: prefer Write over Edit.
- Sequence: Read A → Edit A → Read B → Edit B. Never batch edits without prior reads.
