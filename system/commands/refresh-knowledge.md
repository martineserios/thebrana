# Refresh Knowledge Base

Refresh the dimension docs in brana-knowledge by researching the web for updates, new releases, new content from referenced creators, and emerging relevant work.

## How It Works

For each dimension doc that has external dependencies (skip docs 01-03 which cover internal systems), spawn a **parallel research agent** that:

1. Reads the doc's **Versions:** table in the Refresh Targets section — this is the baseline
2. For each pinned version, checks the Source URL for the latest release and compares
3. Reads the rest of the doc to understand topics, tools, creators, and sources
4. Searches the web for updates since the doc was last reviewed
5. Reports: version deltas, what's new, what changed, what might need updating

**Version deltas are the highest-priority output.** A version bump in a critical dependency (claude-flow, Claude Code) is more actionable than a new blog post.

Run ALL doc research agents **in parallel** using the Task tool with `subagent_type: "general-purpose"`. Use the `model: "haiku"` parameter for cost efficiency since these are web search tasks.

## Research Targets Per Doc

Each agent should search for these categories:

### Category A: Version Delta Check (PRIORITY)
- Read the **Versions:** table in the doc's Refresh Targets section
- For each package with a pinned version: check the Source URL for the latest version
- Report: `package: pinned vX.Y.Z → latest vA.B.C` (or "current" if unchanged)
- For packages with "—" (unpinned): find and report the current version so it can be pinned
- For any version delta: fetch the changelog/release notes and summarize **what changed that affects this doc's content** — new features to leverage, breaking changes to document, deprecations to note
- Severity: HIGH if breaking change or major feature, MEDIUM if minor feature, LOW if patch/bugfix

### Category B: Tool/Platform Updates (beyond version bumps)
- New tools or features not yet in the doc
- Changed APIs, URLs, or documentation locations
- Ecosystem shifts (tool became deprecated, a better alternative emerged)

### Category C: Creator/Author New Content
- New blog posts, talks, or papers from people cited in the doc
- Updated versions of referenced guides or documentation
- New projects from the same creators that are relevant

### Category D: Ecosystem Changes
- New tools, frameworks, or approaches that compete with or complement what the doc covers
- Community adoption changes (something that was niche became mainstream, or vice versa)
- New research papers or industry reports on the doc's topic

### Category E: Relevance Check
- Is the core thesis of the doc still valid?
- Are there new counter-arguments or alternative approaches?
- Has something the doc recommended against become viable (or vice versa)?

## Agent Prompts

For each doc, construct a prompt like:

```
Research updates for enter document [NUMBER] - [TITLE].

Current doc covers: [ONE-LINE SUMMARY FROM DOC]

## STEP 1: Version Delta Check (do this FIRST)

The doc tracks these versions:
[PASTE THE VERSIONS TABLE FROM THE DOC'S REFRESH TARGETS SECTION]

For each package:
- Check the Source URL (npm page, GitHub releases, docs page) for the LATEST version
- Report: "package: pinned vX.Y.Z → latest vA.B.C" (or "→ current" if unchanged)
- For packages pinned as "—": find and report the current latest version
- If a version delta exists: fetch the changelog/release notes between pinned and latest.
  Summarize ONLY changes relevant to what this doc covers. Focus on:
  - New features the doc should mention or leverage
  - Breaking changes that invalidate doc content
  - Deprecations of things the doc recommends

## STEP 2: Broader Research

Key topics to check: [EXTRACTED FROM DOC CONTENT]
Key creators/sources: [EXTRACTED FROM DOC REFERENCES]

Search the web for:
1. New content from: [AUTHORS/CREATORS REFERENCED]
2. New competing or complementary tools/approaches
3. Anything that would invalidate or update the doc's conclusions

## Output Format

### Version Deltas
| Package | Pinned | Latest | Delta |
|---------|--------|--------|-------|
| ... | ... | ... | current / minor / major / breaking |

### Findings
For each finding:
- What's new (with source URL)
- What it affects in the current doc (specific section if possible)
- Severity: HIGH (breaking change or doc conclusion is wrong), MEDIUM (new feature to document or section needs update), LOW (patch bump or new reference)

If nothing significant has changed, say so — "no updates needed" is a valid result.
```

## Doc-Specific Research Focus

Use these as additional search guidance per doc:

| Doc | Focus Areas |
|-----|-------------|
| **04** Claude 4.6 | New Claude model releases, API changes, context window updates, new native capabilities |
| **05** claude-flow v3 | claude-flow GitHub releases, changelog, new MCP tools, architecture changes |
| **06** claude-flow internals | RuVector, SONA, WASM Agent Booster updates, AgentDB changes |
| **07** Integration | New patterns for combining claude-flow with Claude Code |
| **09** Native features | Claude Code changelog, new hook events, new skill/plugin features, subagent updates, memory improvements |
| **10** Statusline | New community statusline projects, Claude Code UI updates |
| **11** Ecosystem | skills.sh new skills count and notable additions, new official plugins, Vercel skills updates, Trail of Bits skills |
| **12** Skill selector | skills.sh registry changes, new skill trust/verification approaches, community patterns for skill management |
| **13** Challenger | New cross-model review patterns, model routing approaches, adversarial review research |
| **15** Self-development | New patterns for self-maintaining AI systems, deploy pipelines, Syncthing alternatives |
| **16** Knowledge health | New AI safety research on knowledge poisoning, hallucination detection, RAG quality |
| **19** PM System Design | New PM tools, AI-native PM approaches, project tracking frameworks, GitHub Projects updates |
| **20-21** Anthropic blog | New Anthropic engineering blog posts since doc was written, new research papers |
| **22** Testing | New testing tools (BATS updates, Promptfoo releases, new eval frameworks), record/playback tools |
| **23** Evaluation | New eval methodologies, benchmark suites, LLM-as-judge improvements, pass@k research |
| **25** Self-documentation | New doc tooling (lychee, Vale, markdownlint releases), new approaches to spec repo maintenance |
| **28** Startup/SMB | Lean startup methodology updates, SMB management frameworks, founder tools, market data |
| **29** Venture Reflection | Venture management patterns, stage-appropriate frameworks, business health metrics |
| **34** Venture OS | Venture operating system tools, business automation, MCP integrations for business ops |

## Output Format

After all agents complete, present a summary:

```markdown
## Version Deltas

| Doc | Package | Pinned | Latest | Impact |
|-----|---------|--------|--------|--------|
| 05 | claude-flow | v3.1.0-alpha.34 | v3.2.0-beta.1 | HIGH — new API |
| 09 | Claude Code | — | 1.0.35 | MEDIUM — new hook event |
| 22 | Promptfoo | — | 0.98.0 | LOW — baselined |
| ... | ... | ... | ... | ... |

## Refresh Results

| Doc | Status | Findings |
|-----|--------|----------|
| 04 | needs update | Claude 4.7 released with X, Y, Z |
| 05 | up to date | No significant changes beyond version bump |
| ... | ... | ... |

## HIGH Priority Updates
[Details — focus on breaking changes and new features to leverage]

## MEDIUM Priority Updates
[Details]

## LOW Priority Updates
[Brief list]

## Version Pins to Update
After applying updates, update these Versions tables:
- Doc 05: claude-flow → v3.2.0-beta.1
- Doc 22: Promptfoo → 0.98.0 (newly pinned)
```

**After applying updates:** Update the `**Versions:**` tables in each affected doc to reflect the new pinned versions. This keeps the baseline current for the next refresh cycle.

## Important Notes

- Skip docs 01, 02, 03 — these cover internal systems (brana v1, nexeye, PM framework) that only the user can update
- Agents should use `WebSearch` and `WebFetch` to gather information
- Each agent should be concise — focus on CHANGES, not re-summarizing what the doc already covers
- If a doc was recently created or reviewed (check `last_reviewed` in frontmatter or git log), note that but still do a quick check
- The goal is a "what changed since we last looked" report, not a full re-research

## Follow-Up

After the refresh report is complete, suggest: "Run `/maintain-specs` to propagate any dimension doc changes through reflection and roadmap layers."

## Rules

- **Ask for clarification whenever you need it.** If findings are contradictory, scope is unclear, or you need the user to prioritize which updates matter — ask. Don't guess.
