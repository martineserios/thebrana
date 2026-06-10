<!-- reconcile phase: Knowledge scope (DECAY): stale dimensions, event log bloat, ruflo noise — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__memory_delete,mcp__ruflo__memory_search,mcp__ruflo__memory_store")

## Knowledge Domain (`--scope knowledge`)

DECAY — weekly scan for staleness, noise, and bloat in the knowledge system (ADR-027, ADR-030).

**Step registry:** ORIENT, ROUTE, KNOW-1, KNOW-2, KNOW-3, KNOW-REPORT

### KNOW-1: Stale dimensions [INTERACTIVE if stale docs found]

Identify dimension docs that are old AND unused.

1. List all `.md` files in `$KNOWLEDGE` (`brana-knowledge/dimensions/`).
2. For each file, check frontmatter for `last_verified:` date. If absent, fall back to last git commit date:
   ```bash
   git -C "$KNOWLEDGE" log -1 --format=%ci -- "$file"
   ```
3. If age > 90 days, check ruflo for recent search hits:
   ```
   mcp__ruflo__memory_search(query: "{doc title from frontmatter or filename}", namespace: "knowledge", limit: 1)
   ```
   If the search returns a result with a recent timestamp (< 90 days), the doc is still in use — skip it.
4. Collect all docs that are > 90 days old AND have no recent ruflo hits into a `stale_dims` list.
5. If `stale_dims` is non-empty, present via AskUserQuestion (multiSelect):
   ```
   "N stale dimensions found (>90 days, no recent search hits).
   Select which to mark stale (adds `stale: true` to frontmatter) or dismiss:"
   ```
   Options: one per stale doc (filename + age), plus "Skip — take no action (Recommended)".
6. For each selected doc, add `stale: true` to its YAML frontmatter (or report only if the doc lives in brana-knowledge and the user prefers manual edits there).

### KNOW-2: Event log bloat [INTERACTIVE if >20 old entries]

Trim old event log entries with a digest summary.

1. Resolve the event log path:
   ```bash
   PROJECT_HASH=$(echo -n "$THEBRANA" | md5sum | cut -d' ' -f1)
   LOG="$HOME/.claude/projects/$PROJECT_HASH/memory/event-log.md"
   ```
   If the file doesn't exist, check `$HOME/.claude/projects/*/memory/event-log.md` via glob. If no log exists, skip KNOW-2.
2. Parse entries. Each entry starts with a date line (e.g., `## YYYY-MM-DD` or `- YYYY-MM-DD:`). Count entries older than 90 days.
3. If > 20 old entries:
   a. Build a digest: group old entries by theme/tag, produce a summary line per theme with count.
   b. Present via AskUserQuestion:
      ```
      "Event log has M entries older than 90 days. Archive to event-log-archive-YYYY.md and keep inline digest?"
      ```
      Options: "Archive + digest", "Skip".
   c. On approval: write old entries to `event-log-archive-{YYYY}.md` (same directory), replace them in the original log with the digest block:
      ```markdown
      ## Archived — YYYY
      > N entries archived to event-log-archive-YYYY.md
      > Themes: theme1 (X), theme2 (Y), ...
      ```
4. If <= 20 old entries, note count in report and move on.

### KNOW-3: Ruflo noise [INTERACTIVE if hard-decay candidates found]

Identify low-value pattern entries for soft or hard decay.

1. Search ruflo for pattern entries:
   ```
   mcp__ruflo__memory_search(query: "*", namespace: "pattern", limit: 50)
   ```
2. For each returned entry, extract `confidence` (from metadata/tags) and age (from `created_at` or date tags). Classify:
   - **Soft decay** (90–180 days old): note in report, no action taken. These are aging but not yet candidates for removal.
   - **Hard decay** (> 180 days old AND confidence < 0.3): candidate for deletion.
3. If hard-decay candidates exist, present via AskUserQuestion (multiSelect):
   ```
   "P ruflo pattern entries are >180 days old with low confidence (<0.3).
   Select entries to delete, or dismiss:"
   ```
   Options: one per candidate (key + age + confidence), plus "Skip — take no action".
4. For each selected entry, delete:
   ```
   mcp__ruflo__memory_delete(key: "{entry_key}", namespace: "pattern")
   ```
   If `memory_delete` is unavailable or fails, log the entry key for manual removal.

### KNOW-REPORT

Present a summary:

```markdown
## Knowledge Domain — DECAY Report

**Date:** YYYY-MM-DD

| Check | Result |
|-------|--------|
| KNOW-1: Stale dimensions | N stale found, M marked |
| KNOW-2: Event log bloat | N old entries, M archived |
| KNOW-3: Ruflo noise | N soft decay, P hard decay deleted |

### Actions Taken
- [list each action, one line]

### No Action Needed
- [list checks that passed clean]
```

Store the report in ruflo (if available):
```
mcp__ruflo__memory_store(key: "decay:brana:{YYYYMMDD}", value: "{JSON summary}", namespace: "pattern", tags: "client:brana,type:decay")
```
If ruflo is unavailable, append summary to `~/.claude/projects/*/memory/MEMORY.md`.

---

