<!-- close phase: Steps 10-11: session metadata + memory review — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

<!-- ruflo preamble -->
ToolSearch("select:mcp__brana__memory_index,mcp__ruflo__memory_store")

> **Skip Steps 10–11 entirely** if `$CLOSE_MODE` is `LIGHT-INLINE` (`--patterns` is extraction only — ADR-053).

### Step 10: Store session metadata

**Via MCP (preferred):**

```
mcp__ruflo__memory_store(
  key: "session-meta:{PROJECT}:{YYYY-MM-DD}",
  value: '{"type": "session-close", "date": "{YYYY-MM-DD}", "commits": N, "learnings": N, "errata": N, "drift": true|false}',
  namespace: "session",
  tags: ["client:{PROJECT}", "type:session-close"],
  upsert: true
)
```

**Fallback (CLI):**

```bash
source "$HOME/.claude/scripts/cf-env.sh"

cd "$HOME" && $CF memory store \
  -k "session:{PROJECT}:{YYYY-MM-DD}" \
  -v '{"type": "session-close", "date": "{YYYY-MM-DD}", "commits": N, "learnings": N, "errata": N, "drift": true|false}' \
  --namespace session \
  --tags "client:{PROJECT},type:session-close" \
  --upsert
```

If both MCP and CLI are unavailable, skip — the handoff note is the fallback.

Then backup:

```bash
# CLI alias: bbackup (or source system/cli/aliases.sh)
"$HOME/.claude/scripts/backup-knowledge.sh" 2>/dev/null || true
```

### Step 11: Memory review

Audit every entry in MEMORY.md using the **"Where to store what"** classification table from `self-improvement.md`.

**MEMORY.md overflow pre-pass** — run before classification audit:

```bash
MEM_PATH="$HOME/.claude/projects/{project-slug}/memory/MEMORY.md"
LINE_COUNT=$(wc -l < "$MEM_PATH" 2>/dev/null || echo 0)
```

**Trimming entries requires two steps** — index-only edits are silently reversed by `mcp__brana__memory_index` at the next session start (it rescans the filesystem and re-adds any `.md` file present in the memory directory):
1. `rm` the `.md` file from disk first.
2. Then remove the index line from MEMORY.md.
Removing only the index line without deleting the file is a no-op. (E2026-06-08-2)

If `LINE_COUNT > 175`:
1. Read the index. For each entry with a file link (`[Title](file.md)`), verify the file exists:
   ```bash
   test -f "$HOME/.claude/projects/{project-slug}/memory/{file.md}" && echo "exists" || echo "dead"
   ```
2. Collect all entries whose linked files are missing (dead links).
3. If any dead-link entries found, delete them from MEMORY.md silently (no AskUserQuestion needed — dead links are always stale).
4. Log count: `Pruned {N} dead-link entries from MEMORY.md ({LINE_COUNT} → {new_count} lines)`.
5. If LINE_COUNT > 175 **after** pruning: report "MEMORY.md is {N} lines — approaching 200-line cap. Consider promoting entries to topic files or CLAUDE.md." Include in Step 12 report under a `⚠ MEMORY.md` line.

Proceed to classification audit only after the overflow pre-pass completes.

1. **Read** `~/.claude/projects/{project-slug}/memory/MEMORY.md`
2. **For each entry**, classify using the full gate:

   | Classification | Action |
   |---------------|--------|
   | **Pattern** (corrective, behavioral, reusable how-to) | Write to `~/.claude/projects/{project}/memory/pattern_{slug}_{date}.md` (Step 5b format, dedup via ruflo) |
   | **Knowledge** (system insight, architecture fact, domain finding) | Append to `~/.claude/memory/knowledge-staging.md` |
   | **Rule/Directive** ("always", "never", "must", "should") | Surface via AskUserQuestion with draft preview — do NOT auto-write; human places in `system/rules/` via `/brana:build` |
   | **Convention** (architecture, stack, domain terms) | Present to user via batched AskUserQuestion: "Convention found — add to CLAUDE.md manually via PR?" Show formatted text. User decides; close does not write. |
   | **Automation** (should trigger on events) | Flag for hook creation — surface as AskUserQuestion, do not auto-write |
   | **Recipe** (multi-step reusable workflow) | Flag for skill creation — surface as AskUserQuestion, do not auto-write |
   | **Log entry** (event that happened) | Move to `/brana:log` |
   | **Derivable** (obtainable via command or file read) | Delete |
   | **Historical** (completed, no future value) | Delete |
   | **Feature idea** (gap, wish, improvement) | Create task via `backlog_add()` (MCP) or `brana backlog add`, then delete |
   | **True memory** (external API, pointers, non-derivable context) | Keep |

   > **Note:** Never route to `system/rules/` or `~/.claude/rules/`. `system/rules/` is BEHAVIORAL_PATHS and requires a worktree — flag as a rule candidate for the user to create via `/brana:build` instead. `~/.claude/rules/` is cleaned by `bootstrap.sh` on every run (rules are loaded via the plugin, not the identity layer).

3. **Before executing any writes**, activate both sentinels so `feedback-gate.sh` and `memory-write-gate.sh` pass through:
   ```bash
   touch /tmp/brana-close-active
   touch /tmp/brana-memory-write-active
   ```

4. **Execute moves** — for directives, write to the appropriate memory file and delete from MEMORY.md.

5. **Feature ideas** — search existing tasks first: `backlog_search(query: "keyword")` (MCP) or `brana backlog search "keyword"`. If duplicate, just delete. If new, `backlog_add(subject: "...", work_type: "...", type: "task")` (MCP) or `brana backlog add --json '{"subject":"...","work_type":"...","type":"task"}'`

6. **After all writes are complete**, clean up both sentinels:
   ```bash
   rm -f /tmp/brana-close-active
   rm -f /tmp/brana-memory-write-active
   ```

7. **Report** — entries moved, deleted, kept, and feature ideas extracted

**Skip if:** session was read-only, or MEMORY.md has fewer than 5 entries.

