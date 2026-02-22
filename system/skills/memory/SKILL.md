---
name: memory
description: "Knowledge system operations — recall patterns, cross-pollinate across projects, review knowledge health. Subcommands: recall, pollinate, review. Use for pattern queries, cross-project transfer, or monthly knowledge audits."
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
---

# Memory

Unified interface for the knowledge system. Replaces `/pattern-recall`, `/cross-pollinate`, and `/knowledge-review`.

## Subcommand Routing

Parse `$ARGUMENTS` for the subcommand:

- `/memory recall [query]` or `/memory [query]` — search patterns (default)
- `/memory pollinate [query]` — cross-project pattern transfer
- `/memory review` — monthly knowledge health audit

If no subcommand recognized, default to **recall** with the full arguments as query. If no arguments at all, infer query from current project context.

## Setup

```bash
source "$HOME/.claude/scripts/cf-env.sh"
```

---

## recall — Query Learned Patterns

1. Use the query from `$ARGUMENTS` (after stripping the `recall` subcommand). If empty, infer from current project context (tech stack, current task, recent errors).

2. **Primary path (claude-flow available):**
   Run `cd $HOME && $CF memory search --query "$QUERY"` to search the memory DB. Parse JSON values to extract `confidence`, `transferable`, and `recall_count` fields.

3. **Fallback path (claude-flow unavailable):**
   Search `~/.claude/projects/*/memory/` for relevant MEMORY.md files. Grep for keywords from the query.

4. **Group results by confidence tier:**

   ```
   ## Proven patterns (confidence >= 0.7)
   - [pattern] — confidence: X, recalls: N, source: PROJECT, transferable: yes/no

   ## Quarantined patterns (confidence >= 0.2, < 0.7)
   - [pattern] — confidence: X, recalls: N, source: PROJECT (treat with caution)

   ## Suspect patterns (confidence < 0.2)
   - [pattern] — confidence: X, recalls: N, source: PROJECT (previously demoted)
   ```

5. If no patterns found, say so explicitly — don't hallucinate past experience.

---

## pollinate — Cross-Project Pattern Transfer

1. Detect current project's tech stack and problem domain.

2. **Primary path:** Run `cd $HOME && $CF memory search --query "$QUERY"` to find patterns across all projects. Filter for **transferable patterns from other projects** only.

3. **Fallback path:** Scan `~/.claude/projects/*/memory/MEMORY.md` from OTHER projects. Grep for technology and pattern type matches.

4. Filter: only show patterns marked `transferable: true` or with confidence > 0.7.

5. For each pattern show: source project, the pattern (problem + solution), confidence, why it might be relevant.

6. Note: cross-pollinated patterns should be validated in the current project context before trusting them.

---

## review — Monthly Knowledge Health Audit

1. **Gather stats** from ReasoningBank:
   - Run `cd $HOME && $CF memory list --namespace patterns --limit 100`
   - For each pattern (skip `test:*`), retrieve: `cd $HOME && $CF memory retrieve -k "KEY" --namespace patterns --format json`
   - Parse: `confidence`, `transferable`, `recall_count`, `project`

2. **Compute health metrics:**

   ```
   ## Knowledge Health Snapshot — YYYY-MM-DD

   ### Overview
   - Total patterns: N
   - By project: project-a (N), project-b (N), ...

   ### Confidence Distribution
   - Proven (>= 0.7): N | Quarantined (0.2-0.7): N | Suspect (< 0.2): N

   ### Transferability
   - Transferable: N | Project-specific: N

   ### Recall Activity
   - Never recalled: N | 1-2 recalls: N | 3+ recalls (promote?): N

   ### Staleness
   - Stored > 60 days, never recalled: N (demotion candidates)
   ```

3. **Flag items:** promotion candidates (3+ recalls, still quarantined), staleness candidates, suspect patterns.

4. **Suggest actions** — present options, let user decide. "Knowledge base looks healthy" is valid.

5. **Backup** if changes made:
   ```bash
   "$HOME/.claude/scripts/backup-knowledge.sh"
   ```

---

## Rules

- **Don't auto-modify patterns.** Review reports and suggests. The user decides.
- **Skip test data.** Entries with keys starting with `test:*` are from the test suite.
- **Ask for clarification whenever you need it.** If the query is too broad, context unclear, or results ambiguous — ask.
