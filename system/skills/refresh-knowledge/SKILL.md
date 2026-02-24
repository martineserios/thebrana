---
name: refresh-knowledge
description: Refresh external research for spec docs — web-search for updates to dimension, venture/PM, and cross-cutting topics. Use when docs may be stale or before major phase planning.
group: brana
context: fork
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - WebSearch
  - Task
---

# Refresh Knowledge

Systematically research updates for spec docs in the enter specs repo. Launches **background** scout agents grouped by topic to avoid context explosion, compiles findings from temp files, then cleans up. Reports only — does not modify docs.

## Usage

`/refresh-knowledge [scope]`

Scope options:
- `all` (default) — research all researchable docs
- `high` — high-priority docs only (04, 05, 09, 11, 20, 21)
- `medium` — medium-priority docs only (06, 13, 22, 23, 25)
- `low` — low-priority docs only (07, 10, 12, 15, 16)
- `venture` — venture/PM docs only (19, 28, 29, 34)
- A specific doc number (e.g., `11`) — research only that doc

## Procedure

1. **Determine scope.** Parse `$ARGUMENTS` for scope keyword or doc number. Default to `all`.

2. **Prepare temp directory.** Run `mkdir -p /tmp/refresh-results`. All agent output goes here — never into main context.

3. **Resolve doc file paths.** Use `Glob` with pattern `??-*.md` in `~/enter_thebrana/enter/` to find all dimension doc filenames. Map doc numbers to actual file paths. Do NOT read the doc contents — only collect the paths.

4. **Build the doc list and groups.** Based on scope, select which groups to launch:

   **Priority tiers:**
   - High: 04, 05, 09, 11, 20, 21
   - Medium: 06, 13, 22, 23, 25
   - Low: 07, 10, 12, 15, 16
   - Venture: 19, 28, 29, 34

   **Groups (topic clusters):**

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
   | J: Venture/PM | 19, 28, 29, 34 | `/tmp/refresh-results/group-j-venture-pm.md` |

   When scope is a single doc, just launch one agent. When scope is a priority tier, only launch the groups that contain docs in that tier.

5. **Launch ALL group agents in background.** For each group, launch a Task agent with:
   - `subagent_type: "scout"` (has Read, Glob, Grep, WebSearch, WebFetch)
   - `model: "haiku"` (cost-efficient for web search tasks)
   - `run_in_background: true` (critical — keeps main context clean)

   **CRITICAL — agents read their own docs.** Do NOT read spec docs or the source registry in the main context. Each agent reads its own docs within its own context window. The main context only provides file paths.

   **Agent prompt template:**
   ```
   Research updates for brana spec documents [NUMBERS] — [TITLES].

   ## Step 1: Read your docs

   Read these files in full:
   - [FULL PATH TO DOC 1]
   - [FULL PATH TO DOC 2]
   - ...

   For each doc, extract:
   - Tool names and version numbers mentioned anywhere
   - Proper nouns (people, organizations, projects, frameworks)
   - Key claims with specific numbers (percentages, benchmarks, counts)
   - URLs embedded in prose or reference sections
   - The `## Refresh Targets` section (Tools, Creators, Searches, URLs)

   ## Step 2: Read the source registry

   Read `~/enter_thebrana/enter/research-sources.yaml` and filter for sources where `relevance` includes any of docs [NUMBERS]. Note their URLs, cadence, trust tier, and last_checked date.

   ## Step 3: Web research

   Using the extracted search material, run web searches for:
   - Each query listed in the Refresh Targets `Searches` subsection
   - Each URL listed in the Refresh Targets `URLs` subsection (via WebFetch)
   - Additional keyword searches: "[tool from doc] new version 2026", "[person cited] new blog posts 2026"
   - Registry sources filtered in step 2

   ## Step 4: Write findings

   For each finding, report:
   - Tag: [NEW], [UPDATE], [CREATOR], or [STALE]
   - What changed (with source URL)
   - Which doc and section it affects
   - Severity: HIGH (doc conclusion wrong), MEDIUM (needs update), LOW (minor)

   Follow the Recursive Discovery archetype:
   - For each new source/creator found that is NOT in the registry, note it as a [REGISTRY] finding
   - For each reference that warrants follow-up, note it as a [LEAD] finding
   - Do not recurse beyond the immediate source — leads will be processed separately by /research

   If nothing significant changed, say so.

   **Write your complete findings to [OUTPUT FILE PATH]**
   ```

   Launch ALL group agents in a **single message** with multiple Task tool calls so they run concurrently.

6. **Wait for all agents to complete.** The system will notify as each finishes. Do NOT read output files until all agents are done (avoid pulling partial results into context).

7. **Compile the summary report.** Once all agents are done, read ONLY the `/tmp/refresh-results/group-*.md` files (not the raw agent transcripts). For each group file, extract:

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

8. **Present actionable summary.** After all per-doc reports:

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

9. **Clean up temp files.** Run: `rm -rf /tmp/refresh-results`

10. **Update registry metadata.** For each source that was checked, propose updating `last_checked` and incrementing `yield_history.checks` in research-sources.yaml. Present as a diff for user approval.

11. **Propagation reminder.** Always end with:

    > **Propagation reminder:** If you update any dimension docs based on these findings, run upward propagation:
    > - Check reflection docs (08, 14) for impacts
    > - Check roadmap docs (17, 18, 19, 24) for impacts
    > - Update `last_reviewed` in frontmatter of any doc you touch

## Design Rationale

- **Agents read their own docs** — the main context never loads spec docs or the registry. This prevents the context explosion that occurs when 20 docs (~120K+ tokens) are loaded before agent dispatch.
- **Background agents** keep research results out of main context. Each agent's full web results (~3-5K tokens) stay in its own context. Only the compiled summary enters the main conversation.
- **Topic grouping** (10 groups vs 20 individual agents) shares context between related docs and reduces overhead while keeping agents focused.
- **Temp file pattern** (`/tmp/refresh-results/`) provides a clean handoff between agents and the compiler step without polluting the workspace.
- **Haiku model** for scouts because these are web-search-and-summarize tasks — Haiku is sufficient and much cheaper.

## Rules

- **NEVER read spec docs or the source registry in the main context.** This is the #1 rule. Agents read their own material.
- **Ask for clarification whenever you need it.** If the scope is ambiguous, findings contradict each other, or you need the user to prioritize which docs to update — ask. Don't guess.
