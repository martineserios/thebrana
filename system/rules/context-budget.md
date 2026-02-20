# Context Budget

## Thresholds

- **<70% context:** proceed normally
- **70-85%:** `/compact` before the next expensive operation
- **>85%:** delegate to a fresh subagent, don't attempt in main context

## Expensive operations

- WebFetch: 50-100K tokens/call. Prefer WebSearch (snippets, ~1K). Metadata-first, fetch only HIGH-priority items.
- 5+ file edits: write a Python script (`/tmp/bulk-edit.py`) instead of individual Read+Edit calls. Run once, review diff, delete script.
- Scouts: must write to temp files, return 2-line summaries only. Read temp files one at a time.

## MCP server overhead

Each MCP server costs 4-17K tokens in tool definitions. Tool Search reduces this ~85%. Before adding a server, estimate tool count impact (~500-2000 tokens/tool). Prefer skills or sub-agents when possible.

## File edit ordering

Read A → Edit A → Read B → Edit B (sequential). Never batch edits without prior reads.
