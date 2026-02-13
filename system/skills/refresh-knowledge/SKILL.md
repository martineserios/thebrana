---
name: refresh-knowledge
description: Refresh external research for dimension docs — web-search for updates to spec topics. Use when dimension docs may be stale or before major phase planning.
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - WebSearch
  - Task
---

# Refresh Knowledge

Systematically research updates for dimension docs in the brana-v2-specs repo. Launches **background** scout agents grouped by topic to avoid context explosion, compiles findings from temp files, then cleans up. Reports only — does not modify docs.

## Usage

`/refresh-knowledge [scope]`

Scope options:
- `all` (default) — research all researchable dimension docs
- `high` — high-priority docs only (04, 05, 09, 11, 20, 21)
- `medium` — medium-priority docs only (06, 13, 22, 23, 25)
- `low` — low-priority docs only (07, 10, 12, 15, 16)
- A specific doc number (e.g., `11`) — research only that doc

## Procedure

1. **Locate the spec repo.** Default: `~/brana-v2-specs`. If `$ARGUMENTS` contains a path, use that instead.

2. **Determine scope.** Parse `$ARGUMENTS` for scope keyword or doc number. Default to `all`.

3. **Prepare temp directory.** Run `mkdir -p /tmp/refresh-results`. All agent output goes here — never into main context.

4. **Build the doc list.** Based on scope, select docs to research:

   **High priority (external tools change fast):**
   - 04: Claude 4.6 capabilities
   - 05: claude-flow v3
   - 09: Claude Code native features
   - 11: Ecosystem (skills, plugins, community)
   - 20: Anthropic blog findings
   - 21: Anthropic engineering deep dive

   **Medium priority (research evolves slower):**
   - 06: claude-flow internals (RuVector, AgentDB, SONA)
   - 13: Challenger agent
   - 22: Testing
   - 23: Evaluation
   - 25: Self-documentation tooling

   **Low priority (mostly stable):**
   - 07: claude-flow + Claude 4.6 integration
   - 10: Statusline research
   - 12: Skill selector
   - 15: Self-development workflow
   - 16: Knowledge health

5. **Extract search material from each doc.** For each doc in scope:

   a. **Read the FULL doc** (not just Refresh Targets). Scan the entire body for:
      - Tool names and version numbers mentioned anywhere
      - Proper nouns (people, organizations, projects, frameworks)
      - Key claims with specific numbers (percentages, benchmarks, counts)
      - URLs embedded in prose or reference sections
      - Concepts and techniques that have searchable names

   b. **Read the `## Refresh Targets` section** and extract:
      - **Tools** to monitor (name + what to check)
      - **Creators** to follow (person/org + what to look for)
      - **Searches** to run (specific web search queries)
      - **URLs** to check (changelogs, release pages, blog indexes)

   c. **Combine both** into the agent prompt. The Refresh Targets are the minimum — doc-body keywords are additional search vectors that catch things the targets missed.

   d. **Read the source registry.** Load `~/enter_thebrana/enter/research-sources.yaml` and filter sources where `relevance` includes any doc number in this group. Include their URLs, cadence, and trust tier in the agent prompt.

6. **Group docs by topic** to reduce agent count and share context between related docs. Use these groupings (adjust if scope is narrower):

   | Group | Docs | Output File |
   |-------|------|-------------|
   | A: Claude Code platform | 04, 09 | `/tmp/refresh-results/group-a-claude-code.md` |
   | B: claude-flow | 05, 06, 07 | `/tmp/refresh-results/group-b-claude-flow.md` |
   | C: Statusline | 10 | `/tmp/refresh-results/group-c-statusline.md` |
   | D: Ecosystem | 11, 12 | `/tmp/refresh-results/group-d-ecosystem.md` |
   | E: Challenger | 13 | `/tmp/refresh-results/group-e-challenger.md` |
   | F: Self-dev + health | 15, 16 | `/tmp/refresh-results/group-f-selfdev-health.md` |
   | G: Anthropic blog | 20, 21 | `/tmp/refresh-results/group-g-anthropic-blog.md` |
   | H: Testing + eval | 22, 23 | `/tmp/refresh-results/group-h-testing-eval.md` |
   | I: Self-documentation | 25 | `/tmp/refresh-results/group-i-self-doc.md` |

   When scope is a single doc, just launch one agent. When scope is a priority tier, only launch the groups that contain docs in that tier.

7. **Launch ALL group agents in background.** For each group, launch a Task agent with:
   - `subagent_type: "scout"` (has Read, Glob, Grep, WebSearch, WebFetch)
   - `model: "haiku"` (cost-efficient for web search tasks)
   - `run_in_background: true` (critical — keeps main context clean)

   Each agent prompt must include:
   - One-paragraph summary of what each doc in the group covers
   - Key claims and numbers from the doc body (extracted in step 5a)
   - The explicit Refresh Targets searches and URLs (from step 5b)
   - Additional keyword searches derived from doc body analysis (from step 5c)
   - Instruction to **write findings to the group's output file** (e.g., `/tmp/refresh-results/group-a-claude-code.md`)
   - The structured report format (see step 9)

   **Agent prompt template:**
   ```
   Research updates for brana-v2-specs documents [NUMBERS] — [TITLES].

   ## What these docs cover
   [1-2 sentences per doc summarizing content and key claims]

   ## Key claims to verify (from doc body)
   - [Specific numbers, versions, counts, benchmarks from the doc prose]
   - [Tool versions mentioned: "X v1.2.3"]
   - [People/orgs cited and their contributions]

   ## Refresh Targets searches
   [Paste the Searches list from each doc's Refresh Targets]

   ## URLs to check
   [Paste the URLs list from each doc's Refresh Targets]

   ## Registry sources (from research-sources.yaml)
   [For each source where relevance includes docs in this group:]
   - [source name] ([trust_tier]): [url] — last checked: [date], cadence: [cadence]
   - Check for: new posts since last_checked, version changes, new references

   ## Additional keyword searches (from doc body analysis)
   - "[keyword from doc body] updates 2026"
   - "[tool mentioned in prose] new version"
   - "[person cited] new blog posts"

   ## Instructions
   For each finding, report:
   - Tag: [NEW], [UPDATE], [CREATOR], or [STALE]
   - What changed (with source URL)
   - Which doc and section it affects
   - Severity: HIGH (doc conclusion wrong), MEDIUM (needs update), LOW (minor)

   Follow the Recursive Discovery archetype from doc 33:
   - For each new source/creator found that is NOT in the registry, note it as a [REGISTRY] finding
   - For each reference that warrants follow-up, note it as a [LEAD] finding
   - Do not recurse beyond the immediate source — leads will be processed separately by /research

   If nothing significant changed, say so.

   **Write your complete findings to /tmp/refresh-results/[GROUP-FILE].md**
   ```

   Launch ALL group agents in a **single message** with multiple Task tool calls so they run concurrently.

8. **Wait for all agents to complete.** The system will notify as each finishes. Do NOT read output files until all agents are done (avoid pulling partial results into context).

9. **Compile the summary report.** Once all agents are done, read ONLY the `/tmp/refresh-results/group-*.md` files (not the raw agent transcripts). For each group file, extract:

   ```
   ## Doc NN: Title
   **Last reviewed:** (from frontmatter or file modification date)
   **Findings:**
   - [NEW] Description of new tool/feature/post — impacts section X — Severity
   - [UPDATE] Description of changed info — current doc says Y, now Z — Severity
   - [CREATOR] New content from person/org — cross-ref with doc NN — Severity
   - [STALE] Specific claim in doc that appears outdated — Severity
   **Suggested action:** Brief recommendation (review, update count, add section, etc.)
   ```

   If a doc has no findings: "No significant changes found."

   Also extract:
   - [REGISTRY] findings → list as "Registry additions proposed"
   - [LEAD] findings → list as "Research leads created"

10. **Present actionable summary.** After all per-doc reports:

    **Summary table:**
    ```markdown
    | Doc | Status | HIGH | MEDIUM | LOW | Top Finding |
    |-----|--------|------|--------|-----|-------------|
    | 04  | needs update | 0 | 2 | 1 | Agent Teams now Research Preview |
    | 05  | up to date | 0 | 0 | 1 | Version bump only |
    | ... | ... | ... | ... | ... | ... |
    ```

    Then list:
    - **HIGH priority updates** — details for anything HIGH severity
    - **Cross-doc implications** — findings that impact multiple docs
    - **Refresh Targets maintenance** — any docs whose Refresh Targets section itself needs updating (new tools to track, stale URLs, etc.)
    - **Registry growth** — new sources/creators discovered across all groups
    - **Leads queue** — references that warrant deeper /research follow-up

11. **Clean up temp files.** Run: `rm -rf /tmp/refresh-results`

12. **Update registry metadata.** For each source that was checked, propose updating `last_checked` and incrementing `yield_history.checks` in research-sources.yaml. Present as a diff for user approval.

13. **Propagation reminder.** Always end with:

    > **Propagation reminder:** If you update any dimension docs based on these findings, run upward propagation:
    > - Check reflection docs (08, 14) for impacts
    > - Check roadmap docs (17, 18, 19, 24) for impacts
    > - Update `last_reviewed` in frontmatter of any doc you touch

## Design Rationale

- **Background agents** prevent context explosion. Each agent's full research (~3-5K tokens of web results) stays in its own context. Only the compiled summary enters the main conversation.
- **Topic grouping** (9 groups vs 16 individual agents) shares context between related docs and reduces overhead while keeping agents focused.
- **Doc-body analysis** catches things Refresh Targets miss. A doc might mention "Syncthing" in prose but not list it in targets. Scanning the full doc ensures comprehensive coverage.
- **Temp file pattern** (`/tmp/refresh-results/`) provides a clean handoff between agents and the compiler step without polluting the workspace.
- **Haiku model** for scouts because these are web-search-and-summarize tasks — Haiku is sufficient and much cheaper.

## Rules

- **Ask for clarification whenever you need it.** If the scope is ambiguous, findings contradict each other, or you need the user to prioritize which docs to update — ask. Don't guess.
