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
brana decisions log main decision "Chose feature strategy for t-348"

# With severity and references
brana decisions log scout finding "Ruflo v3.5.15 released" --severity HIGH --refs doc-05,doc-06

# With target (responding to another entry)
brana decisions log challenger concern "MCP tool count claims inconsistent" --target scout-1:1
```

### Reading entries

```bash
# Last 10 entries
brana decisions read --last 10

# Filter by severity
brana decisions read --severity HIGH

# Last 3 relevant entries (what subagents receive)
brana decisions read --relevant

# Filter by type and agent
brana decisions read --type finding --agent scout

# Raw JSON output
brana decisions read --json
```

### Archiving

```bash
# Archive files older than 30 days (default)
brana decisions archive

# Preview what would be archived
brana decisions archive --dry-run

# Custom threshold
brana decisions archive --days 14
```

**Archive policy (t-1939):** session files dated 30+ days ago are *moved* (never deleted)
to `system/state/decisions/archive/`. Idempotent: a re-run moves nothing, and a file whose
name already exists in `archive/` is left in place rather than overwritten. Nothing runs
`brana decisions archive` automatically yet (scheduling tracked in t-3359), so run it by hand.
The read path does not depend on it for cost: files are read newest first and reading stops
once 3 relevant entries are found, however many old files are still in the active directory.

## How hooks use it

**session-end.sh** writes a session summary entry (type: `action`, severity: `LOW`) with key metrics.

**subagent-context.sh** (SubagentStart) runs `brana decisions read --relevant` and injects the last
3 relevant entries into every spawned subagent. "Relevant" = type `decision`, `finding` or `concern`,
non-blank content, and not a `Session metrics:` line (session-end writes those; they carry no decision).
Hard cap: 3 entries, active files only (archived entries are not read). If the active log holds
only metrics lines, nothing is injected. Each entry is rendered as one line, whitespace-collapsed and
capped at 300 characters, and the block is labelled as untrusted history (entries are free text).

**Requirements and limits, so the feature is not mistaken for automatic:**

- The installed `brana` binary must be newer than this source. An older binary rejects `--relevant`;
  the hook then injects nothing and prints a one-line hint on stderr. `bootstrap.sh` (step 7d)
  reports a stale binary and prints the rebuild command.
- Entries reach the log two ways. `task-completed.sh` writes a `decision` entry
  ("Completed t-NNN (strategy): subject") every time a task is marked completed, so in practice the
  three injected lines are usually the latest task completions. Anything richer (a real decision,
  finding or concern) needs a manual `brana decisions log ...` call. Session-end writes metrics
  lines, which the filter drops on purpose.
- `system/state/decisions/` is gitignored, so a fresh checkout starts with no active entries.

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
