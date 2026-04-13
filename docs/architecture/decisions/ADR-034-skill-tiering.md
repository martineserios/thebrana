# ADR-034: Skill Tiering — Universal Stubs

**Date:** 2026-04-06
**Status:** Accepted (amended 2026-04-06)
**Deciders:** Martin Rios

## Context

CC loads full SKILL.md content at startup, not frontmatter-only (confirmed bug anthropics/claude-code#14882, v2.1.89). With 28 skills (8,392 lines, ~34K tokens), startup takes 4+ minutes. Diagnostic confirmed: removing skills/ makes CC start fast; all other plugin components (hooks, rules, agents, MCP) are fast.

Only 7 skills are used daily. The other 19 are situational (weekly or less).

## Decision

**Original (2026-04-06):** Split skills into core (full SKILL.md) and extended (stubs).

**Amended (2026-04-06):** After deployment, all skills use the stub pattern — including the original 7 "core" skills. Uniform treatment is simpler and works well. The core/extended distinction is removed.

- **All skills:** Stub SKILL.md (frontmatter + Read instruction). Procedure body in `system/procedures/{name}.md`. Loaded on invoke via Read tool.

Stubs preserve full frontmatter (name, description, group, keywords, allowed-tools, status) for discovery, routing, and the skill index. The procedure file path is resolved relative to the plugin root using Glob if needed.

## Consequences

**Positive:**
- Startup context reduced from ~34K to ~8K tokens (76% reduction)
- Cold start improved from 4+ minutes to 30–45 seconds
- All 25 commands remain available as slash commands
- Uniform stub model — no tier management, simpler mental model
- Semantic routing via ruflo unchanged (indexes frontmatter, not body)
- Forward-compatible with CC's future SkillSearch (#43816)

**Negative:**
- All skills add 1 Read round trip on invocation (~200ms), including frequent ones
- Stub instruction is LLM-interpreted — must test reliability
- Path resolution from non-repo CWD requires Glob fallback

**Risks:**
- If CC fixes #14882 (frontmatter-only loading), stubs become unnecessary — merge procedure bodies back into SKILL.md

## References

- Idea doc: `docs/ideas/skill-tiering.md`
- CC bug: anthropics/claude-code#14882 (skills load full content)
- CC bug: anthropics/claude-code#42906 (cold cache API calls)
- Challenger review: 2026-04-06 (Sonnet, simplicity flavor)
