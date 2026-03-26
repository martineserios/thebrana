---
name: memory
description: "Knowledge system operations — recall patterns, cross-pollinate across clients, review knowledge health, audit docs for contradictions. Subcommands: recall, pollinate, review, review --audit. Use for pattern queries, cross-client transfer, monthly knowledge audits, or contradiction detection."
effort: medium
keywords: [knowledge, recall, patterns, cross-pollinate, audit, memory]
task_strategies: [investigation, spike]
stream_affinity: [research, tech-debt]
argument-hint: "[recall|pollinate|review|review --audit] [query]"
group: learning
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - AskUserQuestion
status: stable
growth_stage: evergreen
---

# Memory

Unified interface for the knowledge system. Replaces `/pattern-recall`, `/cross-pollinate`, and `/knowledge-review`.

## Subcommand Routing

Parse `$ARGUMENTS` for the subcommand:

- `/brana:memory recall [query]` or `/brana:memory [query]` — search patterns (default)
- `/brana:memory pollinate [query]` — cross-client pattern transfer
- `/brana:memory review` — monthly knowledge health audit
- `/brana:memory review --audit [doc]` — cross-doc contradiction detection

If no subcommand recognized, default to **recall** with the full arguments as query. If no arguments at all, infer query from current project context.

## Setup

```bash
source "$HOME/.claude/scripts/cf-env.sh"
```

---

## recall — Query Learned Patterns

1. Use the query from `$ARGUMENTS` (after stripping the `recall` subcommand). If empty, infer from current project context (tech stack, current task, recent errors).

2. **Primary path (ruflo available):**
   Run `cd $HOME && $CF memory search --query "$QUERY"` to search the memory DB. Parse JSON values to extract `confidence`, `transferable`, and `recall_count` fields.

3. **Fallback path (ruflo unavailable):**
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

## pollinate — Cross-Client Pattern Transfer

1. Detect current project's tech stack and problem domain.

2. **Primary path:** Run `cd $HOME && $CF memory search --query "$QUERY"` to find patterns across all clients. Filter for **transferable patterns from other clients** only.

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

4. **Suggest actions** — present options, let user decide. If no promotion/demotion/staleness candidates exist and all metrics are within thresholds (quarantine < 30%, staleness < 20%, proven > 50%), report "No action needed" with the numbers.

5. **Backup** if changes made:
   ```bash
   "$HOME/.claude/scripts/backup-knowledge.sh"
   ```

---

## review --audit — Cross-Doc Contradiction Detection

Traverses docs via formal `[doc NN](path)` links and flags factual contradictions. Works at the knowledge layer (doc vs doc), complementing `/brana:reconcile` (spec vs implementation).

### Scope

- `/brana:memory review --audit` — audit all 5 reflections + both CLAUDE.md files (default)
- `/brana:memory review --audit [doc]` — audit a specific doc and everything it links to

### Assertion Types to Extract

| Type | Pattern | Example |
|------|---------|---------|
| **Count** | `N (skills\|agents\|hooks\|rules\|docs\|dimensions\|reflections)` | "34 deployed skills" |
| **Version** | `v\d+\.\d+(\.\d+)?` or version-like strings | "v0.6.0", "all-MiniLM-L6-v2" |
| **Component list** | Markdown tables or bullet lists enumerating named items | Agent table, skill catalog |
| **Architecture claim** | Statements about what components do or how they connect | "claude-flow is the memory layer" |
| **Process claim** | Workflow descriptions with arrows or numbered sequences | "DDD → SDD → TDD", "dimension → reflection → roadmap" |

### Steps

1. **Select target docs.** Default: `reflections/08-diagnosis.md`, `reflections/14-mastermind-architecture.md`, `reflections/29-venture-management-reflection.md`, `reflections/31-assurance.md`, `reflections/32-lifecycle.md`, `.claude/CLAUDE.md`, `system/CLAUDE.md`. Or the single doc specified by user.

2. **Extract assertions.** For each target doc, read it and extract factual claims:
   - Grep for count patterns: `\b\d+\s+(skills?|agents?|hooks?|rules?|commands?|dimensions?|reflections?|patterns?|docs?)\b`
   - Grep for version patterns: `\bv?\d+\.\d+(\.\d+)?\b` in non-URL contexts
   - Identify component lists: tables with `|` separators listing named items
   - Note architecture and process claims in prose

3. **Verify counts against reality.** For verifiable counts:
   - Skills: `ls system/skills/ | wc -l`
   - Agents: count entries in `system/agents/`
   - Rules: `ls system/rules/*.md | wc -l`
   - Hooks: grep hook types in `system/hooks/` or settings.json
   - Dimension docs: `ls docs/dimensions/*.md | wc -l` (via symlink)
   - Reflection docs: `ls docs/reflections/*.md | wc -l`

4. **Cross-reference assertions.** For each assertion, search other docs that mention the same topic (using formal links as the traversal graph). Flag when:
   - Two docs state different counts for the same thing
   - A version number in one doc doesn't match another
   - A component list in doc A has items not in doc B's list (or vice versa)
   - An architecture claim in one doc contradicts another

5. **Report.** Output in errata-compatible format:

   ```
   ## Audit Report — YYYY-MM-DD

   ### Contradictions Found: N

   #### C-001: [title] — SEVERITY
   - **Location:** [doc NN](path.md), line ~N
   - **Claim:** "34 deployed skills"
   - **Reality/Conflict:** actual count is 35 (verified via ls system/skills/)
   - **Suggested fix:** update count to 35

   #### C-002: [title] — SEVERITY
   - **Location:** [doc NN](path.md) vs [doc MM](path.md)
   - **Claim A:** "4 hook types"
   - **Claim B:** "5 hooks: PreToolUse, SessionStart, SessionEnd, PostToolUse, PostToolUseFailure"
   - **Suggested fix:** update doc NN to reflect 5 hook types

   ### Verified Assertions: N
   - Skills count: 35 ✓ (verified in 2 docs)
   - Agent count: 10 ✓ (consistent across 2 docs)
   ...
   ```

6. **Severity classification:**
   - **HIGH**: count or version is wrong (leads to wrong implementation decisions)
   - **MEDIUM**: component list is incomplete or stale (missing items)
   - **LOW**: prose claim is imprecise but not misleading

7. **Offer to apply fixes.** For HIGH/MEDIUM items, propose edits. Don't auto-apply — present and let user decide. If approved, apply as errata to [doc 24](24-roadmap-corrections.md).

---

## Rules

- **Don't auto-modify patterns.** Review reports and suggests. The user decides.
- **Skip test data.** Entries with keys starting with `test:*` are from the test suite.
- **Ask for clarification whenever you need it.** If the query is too broad, context unclear, or results ambiguous — ask.
