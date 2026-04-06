# ADR-034: Skill Tiering — Core + Extended Stubs

**Date:** 2026-04-06
**Status:** Accepted
**Deciders:** Martin Rios

## Context

CC loads full SKILL.md content at startup, not frontmatter-only (confirmed bug anthropics/claude-code#14882, v2.1.89). With 28 skills (8,392 lines, ~34K tokens), startup takes 4+ minutes. Diagnostic confirmed: removing skills/ makes CC start fast; all other plugin components (hooks, rules, agents, MCP) are fast.

Only 7 skills are used daily. The other 19 are situational (weekly or less).

## Decision

Split skills into two tiers:

- **Core (7 skills):** Full SKILL.md with complete procedures. Always loaded.
  - build, backlog, close, research, brainstorm, sitrep, do
- **Extended (19 skills):** Stub SKILL.md (frontmatter + Read instruction). Procedure body in `system/procedures/{name}.md`. Loaded on invoke via Read tool.

Stubs preserve full frontmatter (name, description, group, keywords, allowed-tools, status) for discovery, routing, and the skill index. The procedure file path is resolved relative to the plugin root using Glob if needed.

## Consequences

**Positive:**
- Startup context reduced from ~34K to ~18K tokens (47% reduction)
- All 26 commands remain available as slash commands
- Semantic routing via ruflo unchanged (indexes frontmatter, not body)
- Forward-compatible with CC's future SkillSearch (#43816)

**Negative:**
- Extended skills add 1 Read round trip on invocation (~200ms)
- Stub instruction is LLM-interpreted — must test reliability
- Path resolution from non-repo CWD requires Glob fallback

**Risks:**
- 47% reduction may not be sufficient for <30s target — measure after implementing
- If CC fixes #14882 (frontmatter-only loading), tiering becomes unnecessary — merge stubs back

## References

- Idea doc: `docs/ideas/skill-tiering.md`
- CC bug: anthropics/claude-code#14882 (skills load full content)
- CC bug: anthropics/claude-code#42906 (cold cache API calls)
- Challenger review: 2026-04-06 (Opus, simplicity flavor)
