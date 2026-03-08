---
name: research
description: "Research a topic, doc, or creator — check sources, follow references recursively, produce findings. Use when starting deep research on a topic, creator, or external source."
group: learning
context: fork
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - Write
  - WebSearch
  - WebFetch
  - Task
  - mcp__notebooklm__ask_question
  - mcp__notebooklm__list_notebooks
  - mcp__notebooklm__select_notebook
  - mcp__notebooklm__search_notebooks
  - mcp__notebooklm__get_health
  - AskUserQuestion
---

# Research

The atomic research primitive. Takes a topic, doc number, creator, or lead. Checks sources in the registry, follows references recursively, produces structured findings. Also runs batch knowledge refresh via `--refresh`.

## Usage

`/research [target] [--nlm] [--refresh [scope]]`

Target options:
- A topic (e.g., `/research context engineering`) — find and check sources related to this topic
- A doc number (e.g., `/research 14`) — research updates for this specific dimension doc
- A creator (e.g., `/research creator:simon-willison`) — check a creator's recent output
- `leads` — process queued leads from claude-flow memory (namespace: research-leads)
- `registry` — report on registry health (trust tier distribution, stale sources, cadence overdue)

Flags:
- `--nlm` — Enhance with NotebookLM. Before web research, query relevant notebooks for prior knowledge. After research, prepare findings as a NotebookLM-optimized source file.
- `--refresh [scope]` — Batch refresh mode (replaces `/refresh-knowledge`). Launches parallel scout agents grouped by topic to research updates for dimension docs. Scope: `all` (default), `high`, `medium`, `low`, `venture`, or a doc number. See "Batch Refresh Mode" section below.

## Procedure

1. **Load the source registry.** Read `research-sources.yaml` from brana-knowledge (`~/enter_thebrana/brana-knowledge/research-sources.yaml`). If it doesn't exist, warn the user and fall back to freeform web search.

2. **Determine target type.** Parse `$ARGUMENTS`:
   - If `--refresh` flag is present → batch refresh mode (see "Batch Refresh Mode" below)
   - If it's a number → doc mode (research updates for that doc)
   - If it starts with `creator:` → creator mode (check that creator's channels)
   - If it's `leads` → leads mode (process research-leads from claude-flow memory)
   - If it's `registry` → registry health mode (analyze the YAML)
   - Otherwise → topic mode (search for the topic across registry sources)

3. **Phase 0 — NotebookLM detail extraction (only when `--nlm` flag is present).**

   **CLAUDE:** Check if NotebookLM MCP is available and authenticated:
   ```
   Call mcp__notebooklm__get_health
   → If not authenticated or unavailable, skip Phase 0 with a note: "NotebookLM not available, proceeding with web research only."
   ```

   **CLAUDE:** Search local library for notebooks relevant to the target:
   ```
   Call mcp__notebooklm__search_notebooks with the target topic/keywords
   ```

   **CLAUDE:** For each relevant notebook found (max 2):
   ```
   Call mcp__notebooklm__select_notebook
   ```

   **Prompting strategy (critical — determines quality):**
   - Extract the most specific technical noun from the target. Use that as query anchor.
   - **Never** start queries with broad system names ("brana system", "the architecture") — this triggers canned overview responses from Gemini.
   - Use enumeration framing ("list every", "for each X give Y") — not "explain" or "summarize".

   ```
   Call mcp__notebooklm__ask_question:
   "List all specific numbers, thresholds, version constraints, structural details,
    and named dependencies from your sources about [specific technical noun].
    For each, cite which source and section. If you cannot find something verbatim
    in your sources, say so explicitly rather than stating it as fact."
   ```

   **Canned-response detection:** If the response is < 150 words, matches a generic system overview, or doesn't contain specific facts, discard and retry once with a more specific anchor term. If retry fails, note "Gemini returned no grounded details" and proceed without.

   **CLAUDE:** Compile NotebookLM responses as "Prior Details" — granular facts already documented. Tag each claim `[NLM]`. This shapes the web research:
   - Specific claims to verify or update
   - Gaps in granular detail to fill
   - Numbers or thresholds to cross-check

   Write prior details to `/tmp/research-{target}-nlm-prior.md`. Include in the triage context so web findings are compared against existing knowledge.

4. **Select relevant sources.** Based on target type:
   - **Doc mode**: filter registry sources where `relevance` includes the doc number
   - **Creator mode**: find the creator entry, use all their channels
   - **Topic mode**: search source names/descriptions for topic keywords, plus run web searches
   - **Leads mode**: read leads from `mcp__claude-flow__memory_search` (namespace: `research-leads`, tags: `status:queued`)
   - **Registry mode**: skip to step 9

5. **Phase 1 — Wide Scan (metadata only, no WebFetch).** Launch parallel scouts to scan sources. Each scout:
   - Uses `WebSearch` ONLY — titles, snippets, URLs. **Never WebFetch in Phase 1.**
   - Writes findings to `/tmp/research-{target}-{N}.md` (one file per scout)
   - Returns ONLY a 2-line summary to main context: `"Wrote N findings to /tmp/research-{target}-{N}.md. X HIGH, Y MEDIUM, Z LOW."`
   - Tags findings: `[NEW]`, `[UPDATE]`, `[VERSION]`, `[CREATOR]`, or `[STALE]`
   - **Version check**: compare current version against `version_observed` in registry. If different, tag as `[VERSION]` with HIGH severity
   - **Security scout (mandatory for topic/ecosystem mode)**: one scout must search for CVEs, security advisories, and community trust signals. Tag findings `[SECURITY]`.
   - **Budget**: max 5 scouts for topic mode, max 8 for doc/creator mode (security scout counts toward budget)
   - Scout spawn prompt MUST include: "Write all findings to {filepath}. Return only a 2-line summary with counts. Do NOT use WebFetch."
   - **When `--nlm` prior details exist**: include in scout prompts: "Compare findings against these claims from NotebookLM: [summary from Phase 0]. Tag confirmations as [CONFIRMED], contradictions as [CONTRADICTS-NLM]."

6. **Phase 2 — Triage (main context reads temp files incrementally).** For each temp file from Phase 1:
   - Read ONE temp file at a time (never all at once)
   - Classify each finding: HIGH (doc conclusion wrong, key claim outdated), MEDIUM (needs update), LOW (minor addition)
   - Extract HIGH-priority URLs that need deep reading
   - Summarize the file's findings in 3-5 lines, then move to the next file
   - After all files processed, compile a shortlist of HIGH-priority URLs (max 6)
   - **When `--nlm` prior details exist**, cross-check NLM claims against scout findings:
     - `[CONFIRMED]` — web finding corroborates NLM claim (higher confidence)
     - `[CONTRADICTS-NLM]` — web finding disagrees with NLM claim (NLM may be wrong, investigate)
     - `[NLM-ONLY]` — NLM claim with no web corroboration (flag in report, do not treat as ground truth). This catches Gemini's hallucination pattern: confidently stating specific details that no other source confirms.

7. **Phase 3 — Deep Dive (targeted WebFetch, max 3 scouts).** For HIGH-priority URLs from Phase 2:
   - Launch max 3 scouts, each gets max 2 WebFetch calls
   - Each scout writes deep findings to `/tmp/research-{target}-deep-{N}.md`
   - Each scout returns ONLY a 2-line summary
   - Main context reads deep findings incrementally (same as Phase 2)
   - Note any creators or sources cited that are NOT in the registry

8. **Recurse on new references (max 2 hops, max 3 scouts).** For new sources/creators found in Phase 3:
   - Check if already in registry → if yes, note and skip
   - Launch scouts with the same temp-file protocol (WebSearch only, write to file, return summary)
   - Maximum 3 additional scouts (not 10)
   - Maximum 2 hops deep from the original source
   - Stop recursing when: max depth reached, finding priority drops below MEDIUM, or source already in registry

9. **Connect findings to docs.** For each finding, identify:
   - Which dimension doc(s) it affects
   - Which section within the doc
   - Severity: HIGH (doc conclusion wrong or key claim outdated), MEDIUM (needs update), LOW (minor addition)

10. **Registry health report** (for `registry` mode or appended to other modes):
    - Trust tier distribution (how many proven/promising/unvalidated/demoted)
    - Sources overdue for check (last_checked + cadence < today)
    - Creators with no recent findings (potential demote candidates)
    - Sources with high yield (potential cadence upgrade candidates)

11. **Report findings.** Present structured output:

   ```
   ## Research: [target]
   **Date:** YYYY-MM-DD
   **Sources checked:** N
   **Findings:** H high, M medium, L low

   ### Findings

   #### [NEW] Title — HIGH
   - Source: [name](url)
   - Affects: [doc NN](relative-path.md), section "Section Name"
   - Detail: what changed and why it matters
   - Action: specific suggestion (update claim, add reference, etc.)

   #### [UPDATE] Title — MEDIUM
   ...

   #### [VERSION] Title — HIGH
   - Source: [name](url)
   - Old version: vX.Y.Z (observed: YYYY-MM-DD)
   - New version: vA.B.C
   - Affects: [doc NN](path.md), [doc MM](path.md) (all claims based on old version)
   - Action: re-verify doc claims against new version

   ### New Sources Discovered
   - [source name](url) — type: blog — suggested trust: unvalidated — found via: [parent source]

   ### New Leads Created
   - Lead: "topic or reference" — priority: HIGH/MEDIUM/LOW — reason

   ### Registry Updates Proposed
   - Update last_checked for [sources checked]
   - Add new source: [name]
   - Promote/demote: [source] from [tier] to [tier] — reason
   ```

12. **Create leads for unfollowed threads.** For references that were not recursed into (budget exhausted, low priority):
    - Store as leads in claude-flow memory (namespace: `research-leads`) if available
    - Otherwise, list them in the report under "Leads Created" for manual tracking

13. **Propose registry updates.** List all changes to `research-sources.yaml`:
    - New sources to add (with full schema)
    - `last_checked` date updates
    - `version_observed` + `date_observed` updates (when version changed)
    - Yield history increments
    - Trust tier promotions/demotions (with reasoning)
    - Do NOT modify the YAML directly — present proposals for user approval

14. **Prepare NotebookLM source (only when `--nlm` flag is present).**

    **CLAUDE:** Format the research findings as a NotebookLM-optimized Markdown file following the `/notebooklm-source` template:
    - Executive summary (2-3 sentences: topic, date, key takeaway)
    - H2 sections per finding cluster (not per individual finding)
    - Bold key terms and named entities
    - Bullet points for discrete facts
    - Tables for comparisons or structured data
    - Key Takeaways section at the end
    - Strip all internal cross-references (`[doc NN](path)` → descriptive text)

    **CLAUDE:** Write to `/tmp/notebooklm-research-{target}.md`.

    **CLAUDE:** Report:
    - Word count and validation score
    - "Research findings ready for NotebookLM at `/tmp/notebooklm-research-{target}.md`."

    **YOU:** Upload the file to a NotebookLM notebook. If a relevant notebook exists, add it as a new source. If not, create a new notebook for this topic.

    If prior knowledge was used from Phase 0, note which findings are **new** vs **confirmations** vs **contradictions** of existing notebook content. This helps the user decide whether to replace an old source or add alongside it.

15. **Write to knowledge base (user approval required).** If findings are significant enough to warrant a new dimension doc or major update to an existing one:
    - For a **new topic**: propose creating a new dimension doc in `~/enter_thebrana/brana-knowledge/dimensions/{topic-slug}.md`. Use topic-based filename (not numbered). Present the proposed doc structure and get user approval before writing.
    - For an **existing doc update**: propose specific edits to the relevant dimension doc. Present the changes and get user approval.
    - After writing, commit in brana-knowledge (the post-commit hook auto-reindexes for retrieval).
    - After writing, regenerate INDEX.md: `~/enter_thebrana/thebrana/system/scripts/generate-index.sh`
    - **Skip this step** if findings are minor (LOW severity only) or if the user declines.

## Research Archetypes

When researching, select the appropriate archetype based on the target:

1. **Exhaustive Deep Dive** — read every post/page from a source sequentially. Use for: proven high-yield sources (Anthropic blog). Docs: 20-21.
2. **Ecosystem Catalog** — broad survey of many sources to build inventory. Use for: ecosystem mapping, tool discovery. Docs: 11.
3. **Technical Benchmarking** — focused comparison of specific metrics. Use for: version comparisons, performance claims. Docs: 22-23.
4. **Original Synthesis** — read source code and produce novel analysis. Use for: internal tool understanding. Docs: 05-06.
5. **Recursive Discovery** — follow references from known sources to find new ones. Use for: expanding the registry, finding new creators.

## Architecture

- Main context orchestrates the 3-phase loop. **Main context never does WebFetch or WebSearch directly.**
- Scouts use `subagent_type: "scout"`, `model: "haiku"`, `run_in_background: true`
- **Temp file contract (mandatory):** Scouts write findings to `/tmp/research-{target}-{N}.md`. Scouts return ONLY a 2-line summary via TaskOutput. Main context reads temp files one at a time.
- **Phase budget:** Phase 1 max 5-8 scouts (WebSearch only; one for security in topic/ecosystem mode). Phase 3 max 3 scouts (WebFetch, max 2 per scout). Recursion max 3 scouts.
- **Total scout cap:** max 14 scouts per invocation (8 scan + 3 deep + 3 recurse)
- **Scout spawn prompt template:** Always include these lines in every scout prompt:
  ```
  CRITICAL RULES:
  1. Write ALL findings to {filepath}. Use Bash to write: echo "..." >> {filepath}
  2. Return ONLY a 2-line summary: "Wrote N findings to {filepath}. X HIGH, Y MEDIUM, Z LOW."
  3. Phase 1 scouts: WebSearch ONLY. Never use WebFetch.
  4. Phase 3 scouts: Max 2 WebFetch calls. Write results to file, not to output.
  ```

## Batch Refresh Mode (`--refresh`)

Systematically research updates for brana-knowledge dimension docs. Launches parallel scout agents grouped by topic to check for version deltas, new content from creators, and ecosystem changes. Reports only — does not modify docs. Replaces the former `/refresh-knowledge` command.

### Usage

`/research --refresh [scope]`

Scope: `all` (default), `high`, `medium`, `low`, `venture`, or a specific doc number.

Priority tiers:
- High: 04, 05, 09, 11, 20, 21
- Medium: 06, 13, 22, 23, 25
- Low: 07, 10, 12, 15, 16
- Venture: 19, 28, 29, 34

### Procedure

1. **Prepare temp directory:** `mkdir -p /tmp/refresh-results`
2. **Resolve doc paths** via Glob in `~/enter_thebrana/brana-knowledge/dimensions/`
3. **Group docs by topic** (10 groups: Claude Code, claude-flow, Ecosystem, etc.)
4. **Launch scout agents per group** — all in parallel, background mode:
   - Each scout reads its own docs + research-sources.yaml (main context never loads these)
   - Scouts use WebSearch + WebFetch to check for updates
   - Each writes findings to `/tmp/refresh-results/group-{letter}.md`
5. **Wait for all agents**, then compile summary:
   - Per-doc findings tagged `[NEW]`, `[UPDATE]`, `[VERSION]`, `[STALE]`
   - Summary table with severity counts
   - Registry additions proposed, research leads queued
6. **Clean up:** `rm -rf /tmp/refresh-results`
7. **Propagation reminder:** if updates found, suggest running `/maintain-specs`

### Key rule

**Never read spec docs or the source registry in the main context.** Agents read their own material within their own context windows.

---

## Rules

- **Never modify dimension docs directly.** Report findings, don't apply them.
- **Never modify the registry directly.** Propose changes, let the user approve.
- **Knowledge base writes require approval.** Never auto-create or auto-edit dimension docs. Present the proposal, let the user approve.
- **Respect the phase budgets.** Phase 1: 5-8 scouts. Phase 3: 3 scouts. Recursion: 3 scouts.
- **Temp file protocol is mandatory.** No scout may return full findings via TaskOutput.
- **No WebFetch in Phase 1.** Metadata-first: titles, snippets, URLs only.
- **Read temp files incrementally.** Never read all scout outputs in a single turn.
- **Date-stamp everything.** All findings include the date they were found (YYYY-MM-DD format).
- **Source attribution.** Every finding must link back to the source URL.
- **Security-first for infrastructure research.** Include a security scout in Phase 1 when researching tools that could become production infrastructure.
- **NLM claims are unverified until corroborated.** Gemini is a detail-extraction engine — it recovers specifics Claude compresses but introduces math errors, attribution confusion, and hallucinated references. Tag `[NLM-ONLY]` claims in reports. Never treat NLM output as ground truth.
- **Anchor NLM queries to technical nouns.** Use specific tool names, hook names, thresholds as anchors. Broad system-level framing ("brana system", "the architecture") triggers canned overview responses.
- **Detect canned NLM responses.** If Gemini returns < 150 words or a generic overview, rephrase with a more specific anchor and retry once. Two failures = skip NLM for this query.
