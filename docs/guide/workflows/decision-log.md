# Decision Log

The decision log captures semantic events — decisions, findings, concerns, and actions — as git-tracked JSONL files.

## What it captures

| Type | When to log | Example |
|------|-------------|---------|
| `decision` | A choice was made | "Chose JSONL over SQLite for storage" |
| `finding` | Something discovered | "Spec graph has 19 orphan docs" |
| `concern` | A risk identified | "No test coverage for auth module" |
| `action` | Something done | "Created task t-350", "Opened PR #42" |
| `error` | Something failed | "Build failed: missing dependency" |
| `cost` | Resource tracking | "t-348 routed to opus (score: 0.75)" |

## Usage

### Writing entries

```bash
# Basic entry
uv run python3 system/scripts/decisions.py log main decision "Chose feature strategy for t-348"

# With severity and references
uv run python3 system/scripts/decisions.py log scout finding "Ruflo v3.5.15 released" --severity HIGH --refs doc-05,doc-06

# With target (responding to another entry)
uv run python3 system/scripts/decisions.py log challenger concern "MCP tool count claims inconsistent" --target scout-1:1
```

### Reading entries

```bash
# Last 10 entries
uv run python3 system/scripts/decisions.py read --last 10

# Filter by severity
uv run python3 system/scripts/decisions.py read --severity HIGH

# Filter by type and agent
uv run python3 system/scripts/decisions.py read --type finding --agent scout

# Raw JSON output
uv run python3 system/scripts/decisions.py read --json
```

### Archiving

```bash
# Archive files older than 30 days (default)
uv run python3 system/scripts/decisions.py archive

# Preview what would be archived
uv run python3 system/scripts/decisions.py archive --dry-run

# Custom threshold
uv run python3 system/scripts/decisions.py archive --days 14
```

## How hooks use it

**session-end.sh** writes a session summary entry (type: `action`, severity: `LOW`) with key metrics.

**session-start.sh** reads the last 10 HIGH-severity findings and injects them as context for the new session.

## Entry schema

```jsonl
{"ts":"2026-03-11T12:00:00Z","agent":"main","type":"decision","content":"Chose feature strategy for t-348","refs":["t-348"]}
{"ts":"2026-03-11T12:01:00Z","agent":"scout-1","type":"finding","severity":"HIGH","content":"Ruflo v3.5.15 released","refs":["doc-05","doc-06"]}
```

Required fields: `ts`, `agent`, `type`, `content`
Optional fields: `severity` (HIGH/MEDIUM/LOW), `refs` (array), `target` (string)

## Storage

- Active files: `system/state/decisions/*.jsonl` (last 30 days)
- Archived files: `system/state/decisions/archive/`
- File naming: `YYYY-MM-DD-{session_id}.jsonl`
- Session ID: from `$BRANA_SESSION_ID` env var

## Quick grep

```bash
# All HIGH findings
grep '"severity":"HIGH"' system/state/decisions/*.jsonl

# All cost entries
grep '"type":"cost"' system/state/decisions/*.jsonl

# Everything from a specific session
cat system/state/decisions/2026-03-11-ab3f92c1.jsonl
```

## Comparison with other storage

| System | What it stores | Lifecycle |
|--------|---------------|-----------|
| **Decision log** | Semantic events (decisions, findings) | Git-tracked, 30-day active |
| **MEMORY.md** | Cross-session learnings, preferences | Permanent, curated |
| **ruflo** | Semantic memory, patterns, embeddings | Persistent, searchable |
| **tasks.json** | Work items, status, metadata | Permanent, structured |
| **/tmp session JSONL** | Tool-level telemetry | Deleted at session end |
