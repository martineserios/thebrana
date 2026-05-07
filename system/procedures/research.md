
# Research

The atomic research primitive. Takes a topic, doc number, creator, or lead. Checks sources in the registry, follows references recursively, produces structured findings. Also runs batch knowledge refresh via `--refresh`.

## Usage

`/brana:research [target] [--nlm] [--refresh [scope]] [--strategy research|evaluate|learn|investigate]`

### Strategies

The skill auto-detects strategy from your phrasing (or you can pass `--strategy` explicitly):

- **research** (default) — "What is X?" — produces dimension doc updates
- **evaluate** — "Should we use X or Y?" / "X vs Y" — produces an ADR (decision record)
- **learn** — "I'm starting with X" / "New to X" — produces dimension doc + gotchas + learning path
- **investigate** — "Why is X broken?" / "X is failing" — produces root cause + fix + gotcha

All strategies share the same research flow (source finding, reading, synthesizing). The difference is the output format.

Target options:
- A topic (e.g., `/brana:research context engineering`) — find and check sources related to this topic
- A doc number (e.g., `/brana:research 14`) — research updates for this specific dimension doc
- A creator (e.g., `/brana:research creator:simon-willison`) — check a creator's recent output
- `leads` — process queued leads from ruflo memory (namespace: research-leads)
- `registry` — report on registry health (trust tier distribution, stale sources, cadence overdue)

Flags:
- `--nlm` — Enhance with NotebookLM. Before web research, query relevant notebooks for prior knowledge. After research, prepare findings as a NotebookLM-optimized source file.
- `--refresh [scope]` — Batch refresh mode (replaces `/refresh-knowledge`). Launches parallel scout agents grouped by topic to research updates for dimension docs. Scope: `all` (default), `high`, `medium`, `low`, `venture`, or a doc number. See "Batch Refresh Mode" section below.

## Step Registry

On entry, create a CC Task step registry. Follow the [guided-execution protocol](../_shared/guided-execution.md).

Register these steps: LOAD, ROUTE, LOAD-REGISTRY, INTERNAL-SEARCH, WIDE-SCAN, TRIAGE, DEEP-DIVE, CROSS-REF, REPORT, EXTRACT, EVALUATE, PERSIST.

**Plan mode:** Enter plan mode for INTERNAL-SEARCH, WIDE-SCAN, and TRIAGE (Phases 0-2). Exit plan mode before DEEP-DIVE (Phase 3) which may involve writing temp files.

## Procedure

0. **Step 0 — LOAD.** Pull relevant existing knowledge into context before researching. Budget: 30K tokens max.

   1. **Build query** from available context: `"{project} {task.subject} {task.tags joined} {user_input}"`
   2. **Primary — ruflo MCP (run both in parallel — `namespace: "all"` only returns session records; `specs` namespace is unindexed):**
      ```
      mcp__ruflo__memory_search(query: "{query}", namespace: "knowledge", limit: 4, threshold: 0.4)
      mcp__ruflo__memory_search(query: "{query}", namespace: "pattern",   limit: 3, threshold: 0.4)
      ```
      Merge results, rank by similarity. Focus on: existing dimension docs, `research-sources.yaml` entries, and prior research findings.
   2b. **Graph edge traversal** — see `build.md` LOAD step 2b. Follow `depends_on`/`informs` edges from knowledge results. Max 3 graph-derived docs. Best-effort, never blocks.
   3. **Fallback — tag-based grep** (if MCP unavailable):
      ```bash
      grep -rl "{keywords}" ~/enter_thebrana/brana-knowledge/dimensions/ --include="*.md" | head -5
      grep -rl "{keywords}" ~/enter_thebrana/brana-knowledge/research-sources.yaml | head -1
      ```
      Read the top 3 matching dimension files (first 80 lines each).
   4. **Skill match handling** — if any result has `namespace: "skills"` and score >= 0.5, mention inline: "Matching skill: /brana:{name} ({score})." Informational only — don't auto-invoke or block.
   4a. **JIT skill acquisition** — if no skills match and topic involves a specific technology, offer marketplace search via `Skill(skill="brana:acquire-skills", args="{tech}")`. Read installed procedure into context immediately. See `build.md` LOAD step 4a for full logic and guard rails.
   5. **Summarize loaded knowledge** as a brief context preamble (2-5 bullets). Note what's already documented so research targets gaps, not redundant ground.

1. **Step ROUTE — Determine research strategy.** Classify the request into one of 4 strategies. The strategy determines the output format; the core research flow (source finding, reading, synthesizing) is shared.

   | Strategy | Trigger | Output |
   |----------|---------|--------|
   | **research** (default) | "What is X?" | Dimension doc update/creation |
   | **evaluate** | "Should we use X or Y?" | ADR (decision record) |
   | **learn** | "I'm starting with X tech" | Dimension doc + gotchas + learning path |
   | **investigate** | "Why is X broken?" | Root cause + fix recommendation |

   **Smart router (3-level):**

   **Level 1 — Signal match.** Check `$ARGUMENTS` for keyword patterns:
   - `--strategy <name>` → use explicit strategy
   - Contains "or" / "vs" / "versus" / "compare" / "should we" / "which" → **evaluate**
   - Contains "learn" / "starting with" / "new to" / "getting started" / "how to use" → **learn**
   - Contains "broken" / "why" / "failing" / "debug" / "error" / "not working" / "fix" → **investigate**
   - No match → proceed to Level 2

   **Level 2 — LLM classification.** If no signal match, classify from context:
   ```
   Given this research request: "{$ARGUMENTS}"
   Classify as exactly one of: research, evaluate, learn, investigate.
   - research: general knowledge gathering ("what is X", "how does X work", topic exploration)
   - evaluate: comparing options to make a decision ("X vs Y", "should we use X")
   - learn: onboarding to a new technology ("I need to learn X", "getting started with X")
   - investigate: debugging or root-cause analysis ("X is broken", "why does X fail")
   Reply with ONLY the strategy name.
   ```

   **Level 3 — Ask user.** If still ambiguous (e.g., request could be research or evaluate):
   ```
   AskUserQuestion: "What's your goal with this research?"
   Options: ["Research — learn what X is", "Evaluate — decide between options", "Learn — onboard to new tech", "Investigate — debug a problem"]
   ```

   Set `$STRATEGY` (default: `research`). Log: "Strategy: {$STRATEGY}. Proceeding with shared research flow."

2. **Load the source registry.** Read `research-sources.yaml` from brana-knowledge (`~/enter_thebrana/brana-knowledge/research-sources.yaml`). If it doesn't exist, warn the user and fall back to freeform web search.

3. **Determine target type.** Parse `$ARGUMENTS`:
   - If `--refresh` flag is present → batch refresh mode (see "Batch Refresh Mode" below)
   - If it's a number → doc mode (research updates for that doc)
   - If it starts with `creator:` → creator mode (check that creator's channels)
   - If it's `leads` → leads mode (process research-leads from ruflo memory)
   - If it's `registry` → registry health mode (analyze the YAML)
   - Otherwise → topic mode (search for the topic across registry sources)

4. **Phase 0 — Internal Search (always runs before any web research).**

   Before reaching out to the web, search what the system already knows. Internal docs may have already decided vocabulary, constraints, or conclusions about the topic. External research should deepen what docs sketched, validate assumptions, find implementations, and discover what docs couldn't know.

   **Step A — Cross-namespace semantic search (ruflo MCP, preferred — run in parallel):**

   ```
   mcp__ruflo__memory_search(query: "{TOPIC} {TAGS}", namespace: "knowledge", limit: 8, threshold: 0.4)
   mcp__ruflo__memory_search(query: "{TOPIC} {TAGS}", namespace: "pattern",   limit: 5, threshold: 0.4)
   ```

   Merge and rank by similarity. Group by provenance: knowledge carries authority (dimension docs, ADRs, reflections all land here), patterns are validated heuristics. (`namespace: "all"` and `namespace: "specs"` only return session/empty results — do not use.)

   **If > 10 results with similarity > 0.7:** narrow Phase 1 web search to gaps only.

   **Step A fallback (CLI):** If MCP unavailable, fall back to 4x CLI search:

   ```bash
   source "$HOME/.claude/scripts/cf-env.sh"
   cd "$HOME" && $CF memory search --query "$TOPIC" --namespace knowledge --limit 10 2>/dev/null
   cd "$HOME" && $CF memory search --query "$TOPIC" --namespace assumptions --limit 10 2>/dev/null
   cd "$HOME" && $CF memory search --query "$TOPIC" --namespace field-notes --limit 10 2>/dev/null
   cd "$HOME" && $CF memory search --query "$TOPIC" --namespace decisions --limit 10 2>/dev/null
   ```

   **Step B — Fallback if ruflo entirely unavailable** (MCP and CLI both fail or return nothing):

   - Grep project docs (`docs/`, `system/`, `brana-knowledge/dimensions/`) for the topic keywords
   - Read `~/.claude/projects/*/memory/MEMORY.md` for relevant patterns
   - Check `spec-graph.json` (if it exists) for related nodes and edges:
     ```bash
     uv run python -c "
     import json, sys
     g = json.load(open('spec-graph.json'))
     topic = '$TOPIC'.lower()
     hits = [n for n in g.get('nodes', []) if topic in json.dumps(n).lower()]
     for h in hits[:10]: print(h)
     " 2>/dev/null || true
     ```

   **Step C — Compile internal context.** Note what internal docs already decided:
   - Vocabulary and terminology choices
   - Constraints and requirements
   - Decisions already made (especially ADRs)
   - Open questions that external research should answer
   - Assumptions that need validation

   Write internal context to `/tmp/research-{target}-internal.md`. This shapes all subsequent phases:
   - Scout prompts include: "Internal docs say X about this topic. Verify, deepen, or contradict."
   - Findings that contradict internal decisions get flagged (see cross-reference step below).

   **CLAUDE:** If internal search finds substantial prior knowledge, summarize it before proceeding: "Internal docs cover [topics]. Researching externally to [deepen/validate/discover gaps]."

5. **Phase 0b — NotebookLM detail extraction (only when `--nlm` flag is present).**

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

6. **Select relevant sources.** Based on target type:
   - **Doc mode**: filter registry sources where `relevance` includes the doc number
   - **Creator mode**: find the creator entry, use all their channels
   - **Topic mode**: search source names/descriptions for topic keywords, plus run web searches
   - **Leads mode**: read leads from `mcp__claude-flow__memory_search` (namespace: `research-leads`, tags: `status:queued`)
   - **Registry mode**: skip to step 14

7. **Phase 1 — Wide Scan (metadata only, no WebFetch).** Launch parallel scouts to scan sources. Each scout:
   - Uses `WebSearch` ONLY — titles, snippets, URLs. **Never WebFetch in Phase 1.**
   - Returns ALL findings as structured text in the agent result (scouts cannot write files)
   - **Main context writes** each scout's findings to `/tmp/research-{target}-{N}.md` after receiving the result
   - Tags findings: `[NEW]`, `[UPDATE]`, `[VERSION]`, `[CREATOR]`, or `[STALE]`
   - **Version check**: compare current version against `version_observed` in registry. If different, tag as `[VERSION]` with HIGH severity
   - **Security scout (mandatory for topic/ecosystem mode)**: one scout must search for CVEs, security advisories, and community trust signals. Tag findings `[SECURITY]`.
   - **Budget**: max 5 scouts for topic mode, max 8 for doc/creator mode (security scout counts toward budget)
   - Scout spawn prompt MUST include: "Return ALL findings as structured markdown in your response. Start with a summary line: 'X HIGH, Y MEDIUM, Z LOW findings.' Then list each finding. Do NOT use WebFetch."
   - **When internal context exists (Phase 0)**: include in scout prompts: "Internal docs say the following about this topic: [summary from Phase 0 internal]. Tag findings that confirm internal decisions as [CONFIRMED-INTERNAL], findings that contradict as [CONTRADICTS-INTERNAL], and findings that answer open questions as [ANSWERS-INTERNAL]."
   - **When `--nlm` prior details exist**: include in scout prompts: "Compare findings against these claims from NotebookLM: [summary from Phase 0b]. Tag confirmations as [CONFIRMED], contradictions as [CONTRADICTS-NLM]."

8. **Phase 2 — Triage (main context reads temp files incrementally).** For each temp file from Phase 1:
   - Read ONE temp file at a time (never all at once)
   - Classify each finding: HIGH (doc conclusion wrong, key claim outdated), MEDIUM (needs update), LOW (minor addition)
   - Extract HIGH-priority URLs that need deep reading
   - Summarize the file's findings in 3-5 lines, then move to the next file
   - After all files processed, compile a shortlist of HIGH-priority URLs (max 6)

   **Dedup check (before deep dive):**
   For each finding from Phase 1, compare against top internal result from Phase 0:
   ```
   mcp__ruflo__embeddings_compare(
     text1: "{finding summary}",
     text2: "{top memory_search result}"
   )
   ```
   If similarity > 0.92, mark finding as "already known" and skip deep dive.
   Threshold 0.92 per challenger review — 0.85 risks suppressing contradictions.
   **Fallback:** If MCP unavailable, skip dedup and proceed to deep dive for all HIGH findings.
   - **When `--nlm` prior details exist**, cross-check NLM claims against scout findings:
     - `[CONFIRMED]` — web finding corroborates NLM claim (higher confidence)
     - `[CONTRADICTS-NLM]` — web finding disagrees with NLM claim (NLM may be wrong, investigate)
     - `[NLM-ONLY]` — NLM claim with no web corroboration (flag in report, do not treat as ground truth). This catches Gemini's hallucination pattern: confidently stating specific details that no other source confirms.

9. **Phase 3 — Deep Dive (targeted WebFetch, max 3 scouts).** For HIGH-priority URLs from Phase 2:
   - Launch max 3 scouts, each gets max 2 WebFetch calls
   - Each scout returns ALL deep findings as structured text in the agent result
   - **Main context writes** each scout's findings to `/tmp/research-{target}-deep-{N}.md` after receiving the result
   - Main context reads deep findings incrementally (same as Phase 2)
   - Note any creators or sources cited that are NOT in the registry

10. **Recurse on new references (max 2 hops, max 3 scouts).** For new sources/creators found in Phase 3:
   - Check if already in registry → if yes, note and skip
   - Launch scouts with the same return-inline protocol (WebSearch only, return findings in agent result)
   - Maximum 3 additional scouts (not 10)
   - Maximum 2 hops deep from the original source
   - Stop recursing when: max depth reached, finding priority drops below MEDIUM, or source already in registry

11. **Log HIGH findings to decision log.** Before presenting the report, persist HIGH-severity findings:

   ```bash
   brana decisions log --agent scout --entry-type finding \
     --content "{finding title}: {detail}" \
     --severity HIGH --refs "{affected doc numbers}" 2>/dev/null || true
   ```

   This preserves research findings across sessions (session-start.sh reads HIGH findings). Only log HIGH — MEDIUM/LOW stay in the report only.

12. **Cross-reference findings against internal decisions.** For each finding from Phases 1-3, compare against the internal context from Phase 0:

   - **Confirms**: Finding corroborates an internal decision or assumption. Tag `[CONFIRMED-INTERNAL]`. Higher confidence.
   - **Extends**: Finding adds new information that deepens an internal decision without contradicting it. Tag `[EXTENDS]`.
   - **Answers**: Finding resolves an open question identified in internal docs. Tag `[ANSWERS]` and note which open question.
   - **Contradicts**: Finding disagrees with an internal decision, assumption, or constraint. Tag as:
     ```
     CONTRADICTION: Finding "[finding summary]" contradicts assumption "[assumption text]" in [doc path]. Verify.
     ```
     Contradictions get automatic HIGH severity. List all contradictions in a dedicated "Contradictions" section of the report.

   **CLAUDE:** If any contradictions are found, present them prominently before the main findings list. The user must decide whether to update the internal doc or dismiss the external finding.

13. **Connect findings to docs.** For each finding, identify:
   - Which dimension doc(s) it affects
   - Which section within the doc
   - Severity: HIGH (doc conclusion wrong or key claim outdated), MEDIUM (needs update), LOW (minor addition)

14. **Registry health report** (for `registry` mode or appended to other modes):
    - Trust tier distribution (how many proven/promising/unvalidated/demoted)
    - Sources overdue for check (last_checked + cadence < today)
    - Creators with no recent findings (potential demote candidates)
    - Sources with high yield (potential cadence upgrade candidates)

15. **Report findings.** Present structured output based on `$STRATEGY` (see "Strategy-Specific Output" below for evaluate/learn/investigate formats; the default research format follows):

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

   ### Contradictions with Internal Docs
   (only if Phase 0 found internal context and cross-reference detected contradictions)

   #### CONTRADICTION: [finding summary]
   - Finding: [external source](url) says X
   - Internal: [doc path] assumes/decides Y
   - Impact: what breaks if the external finding is correct
   - Action: verify and update internal doc OR dismiss finding with reasoning

   ### New Sources Discovered
   - [source name](url) — type: blog — suggested trust: unvalidated — found via: [parent source]

   ### New Leads Created
   - Lead: "topic or reference" — priority: HIGH/MEDIUM/LOW — reason

   ### Registry Updates Proposed
   - Update last_checked for [sources checked]
   - Add new source: [name]
   - Promote/demote: [source] from [tier] to [tier] — reason
   ```

### Strategy-Specific Output

When `$STRATEGY` is not `research` (the default), replace step 15's report format with the strategy-specific format below. The shared research flow (steps 2-13) runs identically — only the output structure changes.

#### Strategy: evaluate

Compare N options to produce a decision. Output is always an ADR.

```
## Evaluation: [option A] vs [option B] [vs ...]
**Date:** YYYY-MM-DD | **Strategy:** evaluate
**Decision:** [recommended option] (or "no clear winner — see trade-offs")

### Criteria
| Criterion | Weight | Option A | Option B | ... |
|-----------|--------|----------|----------|-----|
| ...       | ...    | ...      | ...      | ... |

### Per-Option Analysis
#### Option A
- Strengths: ...
- Weaknesses: ...
- Evidence: [source](url)

#### Option B
...

### Recommendation
[1-3 sentences: which option, why, under what conditions]

### Draft ADR
Write a draft ADR to `docs/architecture/decisions/ADR-NNN-{slug}.md` using the project's ADR template.
Status: proposed. Present for user approval before writing.
```

#### Strategy: learn

Onboard to a new technology. Output is a dimension doc with learning-specific sections.

```
## Learn: [technology]
**Date:** YYYY-MM-DD | **Strategy:** learn

### What It Is
[2-3 sentence overview — what the technology does and why it exists]

### Key Concepts
- **Concept A**: [1-line explanation]
- **Concept B**: ...

### Getting Started
1. Install: `command`
2. Configure: ...
3. First use: ...

### Gotchas
- **Gotcha 1**: [what goes wrong] — **Fix**: [how to avoid/resolve]
- **Gotcha 2**: ...

### Learning Path
1. [Resource](url) — [why this first] (estimated time)
2. [Resource](url) — [what it builds on] (estimated time)
3. ...
```

Output: propose a new or updated dimension doc in `brana-knowledge/dimensions/` with `## Gotchas` and `## Learning Path` sections included. Present for user approval.

#### Strategy: investigate

Debug a problem. Structure follows reproduce-hypothesize-test-fix.

```
## Investigation: [problem description]
**Date:** YYYY-MM-DD | **Strategy:** investigate
**Status:** [root cause found | hypothesis only | inconclusive]

### Reproduction
- Steps to reproduce: ...
- Environment: ...
- Frequency: [always | intermittent | once]

### Hypotheses
1. **[Hypothesis A]** — [reasoning] — **Result:** [confirmed | ruled out | untested]
2. **[Hypothesis B]** — ...

### Root Cause
[What actually causes the problem. If inconclusive, state best hypothesis and what evidence is missing.]

### Fix Recommendation
- **Immediate fix**: [what to do now]
- **Proper fix**: [what to do long-term, if different]
- **Prevention**: [how to avoid recurrence]

### Gotcha
> **[technology/area]: [short title]** — [1-2 sentence gotcha for future reference]
```

Output: root cause + fix recommendation. Optionally append a FieldNote (`## Field Notes` or `## Gotchas` section) to the relevant dimension doc. Present for user approval.

---

16. **Create leads for unfollowed threads.** For references that were not recursed into (budget exhausted, low priority):

    **Via MCP (preferred):**
    ```
    mcp__ruflo__memory_store(
      key: "research:{TOPIC}:{finding-slug}",
      value: "{finding summary}",
      namespace: "research-leads",
      tags: ["type:research-finding", "client:{PROJECT}", "tier:episodic", "status:queued"],
      upsert: true
    )
    ```
    **Fallback (CLI):** `$CF memory store` with the same key/namespace/tags.
    - If both unavailable, list them in the report under "Leads Created" for manual tracking

17. **Propose registry updates.** List all changes to `research-sources.yaml`:
    - New sources to add (with full schema)
    - `last_checked` date updates
    - `version_observed` + `date_observed` updates (when version changed)
    - Yield history increments
    - Trust tier promotions/demotions (with reasoning)
    - Do NOT modify the YAML directly — present proposals for user approval

18. **Prepare NotebookLM source (only when `--nlm` flag is present).**

    **CLAUDE:** Format the research findings as a NotebookLM-optimized Markdown file following the `/brana:notebooklm-source` template:
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

19. **Write to knowledge base (user approval required).** If findings are significant enough to warrant a new dimension doc or major update to an existing one:
    - For a **new topic**: propose creating a new dimension doc in `~/enter_thebrana/brana-knowledge/dimensions/{topic-slug}.md`. Use topic-based filename (not numbered). Present the proposed doc structure and get user approval before writing.
    - For an **existing doc update**: propose specific edits to the relevant dimension doc. Present the changes and get user approval.
    - After writing, commit in brana-knowledge (the post-commit hook auto-reindexes for retrieval).
    - After writing, regenerate INDEX.md: `~/enter_thebrana/thebrana/system/scripts/generate-index.sh`
    - **Skip this step** if findings are minor (LOW severity only) or if the user declines.

20. **Step EXTRACT — Identify what was learned.** At research end, distill findings into typed knowledge units.

    1. Compare initial research question against findings — what was answered, what remains open
    2. Classify each finding:
       - **New facts** about the topic (not previously documented)
       - **Contradictions** to existing knowledge (flag for resolution)
       - **Patterns** across multiple sources (reusable insights)
       - **Gaps** identified (leads for future research)
    3. Assign ontology type to each:
       - **Dimension** — new or updated topic doc in brana-knowledge
       - **Pattern** — reusable insight applicable beyond this research
       - **FieldNote** — practical gotcha or implementation detail
       - **ADR** — architectural decision implied by research findings
    4. Flag sources not yet in `brana-knowledge/research-sources.yaml` for addition

21. **Step EVALUATE — Score and gate each finding.**

    Score each extracted finding (0-10) and apply the gate:

    | Size | Scope | Novelty | Gate |
    |------|-------|---------|------|
    | SMALL (0-1) | Single fact, URL, tag | Already documented | Auto-persist |
    | MEDIUM (2-4) | Dimension doc update | New on existing topic | Dedup via ruflo, present to user |
    | LARGE (5+) | New dimension, contradicts existing | Brand new topic area | User review, suggest challenger for contradictions |

    **Dedup check (MEDIUM+ only — run in parallel):**
    ```
    mcp__ruflo__memory_search(query: "{finding summary}", namespace: "knowledge", limit: 2)
    mcp__ruflo__memory_search(query: "{finding summary}", namespace: "pattern",   limit: 2)
    ```
    If top result similarity > 0.92, mark as "already stored" and skip persist. Otherwise proceed.

    **Fallback:** If ruflo unavailable, present all MEDIUM+ findings to user without dedup.

22. **Step PERSIST — Route findings to storage.**

    | Type | Destination | Auto/Prompted |
    |------|------------|---------------|
    | Dimension update | Append to existing doc in `brana-knowledge/dimensions/` | Prompted |
    | New dimension | Create new doc in `brana-knowledge/dimensions/` | Always prompted (LARGE) |
    | Pattern | ruflo `namespace: "pattern"` + memory file | SMALL: auto, MEDIUM+: prompted |
    | Source | Append to `brana-knowledge/research-sources.yaml` | Auto |
    | FieldNote | Append to relevant doc `## Field Notes` section | Prompted |

    **Pattern persist (auto for SMALL):**
    ```
    mcp__ruflo__memory_store(
      key: "pattern:research:{topic}:{slug}",
      value: "{pattern description}",
      namespace: "pattern",
      tags: ["type:pattern", "source:research", "topic:{topic}"],
      upsert: true
    )
    ```

    **Source persist (auto):** Append new sources to `research-sources.yaml` with `trust: unvalidated`, today's date as `last_checked`.

    **Fallback:** If ruflo unavailable, write patterns to `~/.claude/projects/*/memory/` as markdown entries. List all persisted items in the report footer.

## Research Archetypes

When researching, select the appropriate archetype based on the target:

1. **Exhaustive Deep Dive** — read every post/page from a source sequentially. Use for: proven high-yield sources (Anthropic blog). Docs: 20-21.
2. **Ecosystem Catalog** — broad survey of many sources to build inventory. Use for: ecosystem mapping, tool discovery. Docs: 11.
3. **Technical Benchmarking** — focused comparison of specific metrics. Use for: version comparisons, performance claims. Docs: 22-23.
4. **Original Synthesis** — read source code and produce novel analysis. Use for: internal tool understanding. Docs: 05-06.
5. **Recursive Discovery** — follow references from known sources to find new ones. Use for: expanding the registry, finding new creators.

## Architecture

- Main context orchestrates the 3-phase loop. **Main context never does WebFetch or WebSearch directly.**
- Scouts use `subagent_type: "brana:scout"`, `run_in_background: true`
- **Return-inline contract (mandatory):** Scouts return ALL findings as structured text in their agent result. **Scouts cannot write files** (no Bash/Write tools). Main context receives findings and writes to `/tmp/research-{target}-{N}.md` one at a time.
- **Phase budget:** Phase 1 max 5-8 scouts (WebSearch only; one for security in topic/ecosystem mode). Phase 3 max 3 scouts (WebFetch, max 2 per scout). Recursion max 3 scouts.
- **Total scout cap:** max 14 scouts per invocation (8 scan + 3 deep + 3 recurse)
- **Model routing for scouts:** Phase 1 scouts (metadata-only WebSearch) use `model: "haiku"`. Phase 3 scouts (deep-dive WebFetch) use `model: "sonnet"`. This optimizes cost — scan scouts do lightweight work, deep-dive scouts need stronger comprehension.
- **Scout spawn prompt template:** Always include these lines in every scout prompt:
  ```
  CRITICAL RULES:
  1. Return ALL findings as structured markdown in your response.
  2. Start with a summary line: "X HIGH, Y MEDIUM, Z LOW findings."
  3. Then list each finding with tags, source URL, severity, and detail.
  4. Phase 1 scouts: WebSearch ONLY. Never use WebFetch.
  5. Phase 3 scouts: Max 2 WebFetch calls.
  ```

## Batch Refresh Mode (`--refresh`)

Systematically research updates for brana-knowledge dimension docs. Launches parallel scout agents grouped by topic to check for version deltas, new content from creators, and ecosystem changes. Reports only — does not modify docs. Replaces the former `/refresh-knowledge` command.

### Usage

`/brana:research --refresh [scope]`

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
   - Each returns ALL findings as structured text in the agent result (scouts cannot write files)
   - **Main context writes** each group's findings to `/tmp/refresh-results/group-{letter}.md` after receiving
5. **Wait for all agents**, then compile summary:
   - Per-doc findings tagged `[NEW]`, `[UPDATE]`, `[VERSION]`, `[STALE]`
   - Summary table with severity counts
   - Registry additions proposed, research leads queued
6. **Clean up:** `rm -rf /tmp/refresh-results`
7. **Propagation reminder:** if updates found, suggest running `/brana:maintain-specs`

### Key rule

**Never read spec docs or the source registry in the main context.** Agents read their own material within their own context windows.

---

## Rules

- **Internal before external.** Phase 0 (internal search) always runs before any web research. Never launch web research and internal doc reading in parallel. Web results without internal context produce generic findings instead of project-specific ones.
- **Contradiction flagging is mandatory.** If external findings contradict an internal assumption or decision, flag it with `CONTRADICTION:` prefix and HIGH severity. The user must resolve contradictions explicitly.
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
- **Step registry.** Follow the [guided-execution protocol](../_shared/guided-execution.md). Register steps on entry, update as each phase completes.

---

## Resume After Compression

If context was compressed and you've lost track of progress:

1. Call `TaskList` — find CC Tasks matching `/brana:research — {STEP}`
2. The `in_progress` task is your current phase — resume from there
3. Read temp files in `/tmp/research-{target}-*.md` for prior phase outputs
