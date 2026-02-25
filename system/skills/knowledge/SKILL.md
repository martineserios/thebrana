---
name: knowledge
description: "Browse, annotate, review, and reindex the knowledge base. Use when managing brana-knowledge dimension docs."
group: learning
context: fork
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - Task
  - Write
  - Edit
---

# Knowledge

Manage the brana-knowledge dimension docs — browse, review staleness, annotate, and reindex.

## Usage

`/knowledge [subcommand]`

Subcommands:
- (no args) or `browse` — Show the index, let user pick a doc to read
- `review` — Staleness check across all docs and sources
- `annotate [doc]` — Edit a dimension doc (on a branch)
- `reindex` — Full reindex of all dimension docs into claude-flow memory
- `reindex [file]` — Reindex a specific file
- `index` — Regenerate dimensions/INDEX.md

## Paths

```bash
KNOWLEDGE="$HOME/enter_thebrana/brana-knowledge"
DIMENSIONS="$KNOWLEDGE/dimensions"
SOURCES="$KNOWLEDGE/research-sources.yaml"
INDEXER="$HOME/enter_thebrana/thebrana/system/scripts/index-knowledge.sh"
INDEX_GEN="$HOME/enter_thebrana/thebrana/system/scripts/generate-index.sh"
```

## Procedure

### 0. Validate environment

Check that `$KNOWLEDGE` exists. If not, tell the user: "brana-knowledge not found at ~/enter_thebrana/brana-knowledge. Clone it first."

### 1. Parse subcommand

Parse `$ARGUMENTS` to determine which subcommand to run.

### 2. Execute subcommand

#### browse (default)

1. Read `$DIMENSIONS/INDEX.md`
2. Show the table to the user
3. Ask which doc they want to read
4. Read and display the selected doc

#### review

1. For each `.md` file in `$DIMENSIONS` (excluding INDEX.md):
   ```bash
   git -C "$KNOWLEDGE" log -1 --format="%ci" -- "dimensions/$(basename "$file")"
   ```
2. Flag docs not updated in 90+ days as stale
3. If `$SOURCES` exists, check for sources overdue by their `cadence` field
4. Report:
   ```
   ## Knowledge Review
   ### Stale Docs (90+ days)
   | Doc | Last Updated | Days Ago |
   ...
   ### Sources Overdue
   | Source | Cadence | Last Checked | Overdue By |
   ...
   ### Summary
   - Total docs: N
   - Stale: N
   - Sources overdue: N
   ```

#### annotate [doc]

1. Find the doc by name or number (e.g., `annotate 13` → `13-challenger-agent.md`, `annotate design-thinking` → `38-design-thinking.md`)
2. Create a branch in brana-knowledge: `docs/annotate-{doc-slug}`
3. Read the doc, present to user
4. Apply user's edits
5. Commit — the post-commit hook auto-reindexes
6. Merge back to master and clean up

#### reindex / reindex [file]

1. Source NVM: `export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"`
2. Run: `"$INDEXER"` (all) or `"$INDEXER" "$DIMENSIONS/{file}"` (specific)
3. Report stats from the script output

#### index

1. Run: `"$INDEX_GEN"`
2. Commit the updated INDEX.md in brana-knowledge
3. Report the result

## Rules

- Always validate `$KNOWLEDGE` exists before any operation
- For `annotate`, follow git-discipline — work on a branch, merge when done
- `reindex` requires NVM sourcing for node access
- Report findings concisely — don't dump raw git output
- INDEX.md is auto-generated — never edit it manually
