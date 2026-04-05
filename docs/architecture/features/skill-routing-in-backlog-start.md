---
depends_on:
  - docs/architecture/decisions/ADR-026-ruflo-mcp-backbone.md
  - docs/architecture/features/task-management-system.md
informs:
  - docs/architecture/features/acquire-skills.md
---
# Feature: Skill Routing in Backlog Start

**Date:** 2026-04-01
**Status:** implemented
**Task:** t-833
**Idea doc:** docs/ideas/skill-auto-router.md
**ADR:** ADR-026 (ruflo MCP backbone)

## Goal

When `brana backlog start <id>` runs, automatically suggest the best skill for the task
using semantic search against indexed skill frontmatter in ruflo memory. If no local skill
matches well, offer to search external marketplaces.

## Audience

The brana operator — reducing cognitive load of "which /brana: command do I need?"

## Constraints

- Must work without ruflo (CLI `brana skills suggest` as fallback)
- No auto-invoke — always suggest via AskUserQuestion, user confirms
- No new MCP server — uses existing `memory_search(ns: "skills")` from ruflo
- Skills must be indexed first (`index-skills.sh`, runs at session-start)
- Must not slow down `backlog start` noticeably (37ms HNSW is acceptable)

## Scope

### What changes in `/brana:backlog start`

**Step 5 (Skill suggestion)** is rewritten. Currently calls `brana skills suggest --task <id>`.
New behavior:

```
Step 5: Skill suggestion (after strategy confirmed)

  5a. Read task metadata: subject, tags, strategy, stream, description
  5b. Build query: "{subject} {tags joined} {strategy}"
  5c. Try MCP:
      mcp__ruflo__memory_search(
        query: "{query from 5b}",
        namespace: "skills",
        limit: 5,
        threshold: 0.3
      )
  5d. If MCP unavailable, try CLI:
      brana skills suggest --task <id>
  5e. Present results based on confidence:
      - Top result > suggest_threshold (default 0.5):
        AskUserQuestion: "Suggested skill: /brana:{name} (score: {N})"
        Options: ["Run /brana:{name}", other matches, "Skip — none needed"]
      - Top result 0.3–0.5:
        Mention inline: "Possible match: /brana:{name} ({score})" — no AskUserQuestion
      - All results < 0.3:
        If task is code execution, offer marketplace search:
        AskUserQuestion: "No local skill matches. Search externally?"
        Options: ["Search externally", "Skip"]
        If yes → Skill(skill="brana:acquire-skills", args="{subject keywords}")
      - No results (ruflo down + CLI fails):
        Skip silently
```

### What changes in backlog SKILL.md frontmatter

Add to allowed-tools:
```
- mcp__ruflo__memory_search
```

### Configuration

Read thresholds from `~/.claude/tasks-config.json`:

```json
{
  "skill_routing": {
    "suggest_threshold": 0.5,
    "mention_threshold": 0.3,
    "enabled": true
  }
}
```

If not configured, use defaults. If `enabled: false`, skip step 5 entirely.

### `/brana:do` alias (t-834, separate task)

A thin alias skill that parses freeform text, creates a quick task in-memory, and calls
the same routing logic. Not in scope for t-833.

## Key Files

| File | Change |
|------|--------|
| `system/skills/backlog/SKILL.md` | Rewrite step 5, add MCP tool to allowed-tools |
| `tests/skills/test_skill_routing.sh` | New test: routing logic, fallback, thresholds |

## Not in scope

- Silent routing (auto-invoke without asking) — deferred
- `/brana:do` alias — separate task t-834
- Marketplace auto-trigger — separate task t-841
- Cross-client intelligence — deferred to P4
- Configurable thresholds UI — separate task t-835
