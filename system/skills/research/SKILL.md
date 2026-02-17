---
name: research
description: "Research a topic, doc, or creator — check sources, follow references recursively, produce findings. Use when starting deep research on a topic, creator, or external source."
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - WebSearch
  - WebFetch
  - Task
---

# Research

The atomic research primitive. Takes a topic, doc number, creator, or lead. Checks sources in the registry, follows references recursively, produces structured findings. Can be invoked standalone for ad-hoc research or called by `/refresh-knowledge` for batch operations.

## Usage

`/research [target]`

Target options:
- A topic (e.g., `/research context engineering`) — find and check sources related to this topic
- A doc number (e.g., `/research 14`) — research updates for this specific dimension doc
- A creator (e.g., `/research creator:simon-willison`) — check a creator's recent output
- `leads` — process queued leads from claude-flow memory (namespace: research-leads)
- `registry` — report on registry health (trust tier distribution, stale sources, cadence overdue)

## Procedure

1. **Load the source registry.** Read `research-sources.yaml` from the enter repo (`~/enter_thebrana/enter/research-sources.yaml`). If it doesn't exist, warn the user and fall back to freeform web search.

2. **Determine target type.** Parse `$ARGUMENTS`:
   - If it's a number → doc mode (research updates for that doc)
   - If it starts with `creator:` → creator mode (check that creator's channels)
   - If it's `leads` → leads mode (process research-leads from claude-flow memory)
   - If it's `registry` → registry health mode (analyze the YAML)
   - Otherwise → topic mode (search for the topic across registry sources)

3. **Select relevant sources.** Based on target type:
   - **Doc mode**: filter registry sources where `relevance` includes the doc number
   - **Creator mode**: find the creator entry, use all their channels
   - **Topic mode**: search source names/descriptions for topic keywords, plus run web searches
   - **Leads mode**: read leads from `mcp__claude-flow__memory_search` (namespace: `research-leads`, tags: `status:queued`)
   - **Registry mode**: skip to step 8

4. **Scan sources (Wide Scan).** For each relevant source:
   - Use `WebSearch` with the source URL/name + recent date qualifiers (2025-2026)
   - Use `WebFetch` for specific URLs that have known content (changelogs, blog indexes)
   - Extract: new posts/releases, version changes, new claims, referenced creators
   - **Version check**: compare current version against `version_observed` in registry. If different, tag as `[VERSION]` finding with HIGH severity — all doc claims based on the old version need re-verification
   - Tag each finding: `[NEW]`, `[UPDATE]`, `[VERSION]`, `[CREATOR]`, or `[STALE]`

5. **Deep Dive on high-signal findings.** For findings tagged HIGH severity:
   - Read the full source content with `WebFetch`
   - Extract specific claims, numbers, architectures, and references
   - Note any creators or sources cited that are NOT in the registry

6. **Recurse on new references (up to 3 hops).** For each new source/creator found:
   - Check if already in registry → if yes, note and skip
   - If not in registry, launch a scout agent (`subagent_type: "scout"`, `model: "haiku"`) to check the reference
   - Maximum 10 scout agents total (budget cap)
   - Maximum 3 hops deep from the original source
   - Stop recursing when: max depth reached, finding priority drops below MEDIUM, or source already in registry

7. **Connect findings to docs.** For each finding, identify:
   - Which dimension doc(s) it affects
   - Which section within the doc
   - Severity: HIGH (doc conclusion wrong or key claim outdated), MEDIUM (needs update), LOW (minor addition)

8. **Registry health report** (for `registry` mode or appended to other modes):
   - Trust tier distribution (how many proven/promising/unvalidated/demoted)
   - Sources overdue for check (last_checked + cadence < today)
   - Creators with no recent findings (potential demote candidates)
   - Sources with high yield (potential cadence upgrade candidates)

9. **Report findings.** Present structured output:

   ```
   ## Research: [target]
   **Date:** YYYY-MM-DD
   **Sources checked:** N
   **Findings:** H high, M medium, L low

   ### Findings

   #### [NEW] Title — HIGH
   - Source: [name](url)
   - Affects: doc NN, section "Section Name"
   - Detail: what changed and why it matters
   - Action: specific suggestion (update claim, add reference, etc.)

   #### [UPDATE] Title — MEDIUM
   ...

   #### [VERSION] Title — HIGH
   - Source: [name](url)
   - Old version: vX.Y.Z (observed: YYYY-MM-DD)
   - New version: vA.B.C
   - Affects: docs NN, MM (all claims based on old version)
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

10. **Create leads for unfollowed threads.** For references that were not recursed into (budget exhausted, low priority):
    - Store as leads in claude-flow memory (namespace: `research-leads`) if available
    - Otherwise, list them in the report under "Leads Created" for manual tracking

11. **Propose registry updates.** List all changes to `research-sources.yaml`:
    - New sources to add (with full schema)
    - `last_checked` date updates
    - `version_observed` + `date_observed` updates (when version changed)
    - Yield history increments
    - Trust tier promotions/demotions (with reasoning)
    - Do NOT modify the YAML directly — present proposals for user approval

## Research Archetypes

When researching, select the appropriate archetype based on the target:

1. **Exhaustive Deep Dive** — read every post/page from a source sequentially. Use for: proven high-yield sources (Anthropic blog). Docs: 20-21.
2. **Ecosystem Catalog** — broad survey of many sources to build inventory. Use for: ecosystem mapping, tool discovery. Docs: 11.
3. **Technical Benchmarking** — focused comparison of specific metrics. Use for: version comparisons, performance claims. Docs: 22-23.
4. **Original Synthesis** — read source code and produce novel analysis. Use for: internal tool understanding. Docs: 05-06.
5. **Recursive Discovery** — follow references from known sources to find new ones. Use for: expanding the registry, finding new creators.

## Architecture

- Main context orchestrates the research loop
- Background Haiku scouts for parallel source scanning (max 10 concurrent)
- Scouts use `subagent_type: "scout"`, `model: "haiku"`, `run_in_background: true`
- Findings written to temp files (`/tmp/research-[target]-*.md`) to avoid context explosion
- Main context compiles from temp files after all scouts complete

## Rules

- **Never modify dimension docs directly.** Report findings, don't apply them.
- **Never modify the registry directly.** Propose changes, let the user approve.
- **Respect the budget cap.** Maximum 10 scout agents per invocation.
- **Date-stamp everything.** All findings include the date they were found (2026-02-12 format).
- **Source attribution.** Every finding must link back to the source URL.
