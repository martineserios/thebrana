---
status: accepted
---
# ADR-034: Skill Tiering — Universal Stubs

**Date:** 2026-04-06
**Status:** Accepted (amended 2026-04-06)
**Deciders:** Martin Rios

## Context

CC loads full SKILL.md content at startup, not frontmatter-only (confirmed bug anthropics/claude-code#14882, v2.1.89). With the full skill set loaded (~34K tokens at the time of diagnosis), startup takes 4+ minutes. Diagnostic confirmed: removing skills/ makes CC start fast; all other plugin components (hooks, rules, agents, MCP) are fast.

Most skills are situational (weekly or less). A small subset is used in nearly every session. See `docs/reference/skills.md` for the current full list.

## Decision

**Original (2026-04-06):** Split skills into core (full SKILL.md) and extended (stubs).

**Amended (2026-04-06):** After deployment, all skills use the stub pattern — including the original 7 "core" skills. Uniform treatment is simpler and works well. The core/extended distinction is removed.

- **All skills:** Stub SKILL.md (frontmatter + Read instruction). Procedure body in `system/procedures/{name}.md`. Loaded on invoke via Read tool.

Stubs preserve full frontmatter (name, description, group, keywords, allowed-tools, status) for discovery, routing, and the skill index. The procedure file path is resolved relative to the plugin root using Glob if needed.

**Amended (2026-06-10, t-1941):** The Risks clause fired — native Claude Code now lazy-loads SKILL.md bodies (frontmatter-only at session start), so the stub's extra Read hop no longer buys startup time and is itself the failure layer behind recurring procedure-Read errors. Procedure bodies merge back into SKILL.md for every 1:1 case:

- **Default:** SKILL.md carries the full procedure body inline. No stub, no `system/procedures/{name}.md` counterpart.
- **Transitional exception (big four):** `build`, `close`, `backlog`, `reconcile` keep stubs until their phase-split lands (t-1942) — their bodies exceed reliable single-load size. No other stub may be created; validate.sh enforces a named allowlist.
- **`system/procedures/` retains** only the big-four bodies and knowledge docs with no SKILL.md counterpart (migrate.md). Acquired skills (`system/skills/acquired/*/`) were also 1:1 stub→procedure pairs and are inlined the same way — their curated stub frontmatter (provenance, allowed-tools) wins over the upstream frontmatter embedded in the procedure file.

**Deploy requirement:** the plugin cache (`~/.claude/plugins/cache/brana/brana/1.0.0/`) is an rsync copy made by bootstrap.sh. The bootstrap sync is part of the migration itself — a merge without the sync leaves deployed stubs pointing at deleted procedure files. Sessions in flight during the migration window may observe a split state; restart them.

**Rollback:** revert the t-1941 merge commit, then re-run the bootstrap sync. Both steps are required — reverting without re-syncing leaves the cache on the inlined layout.

## Consequences

**Positive:**
- Startup context reduced from ~34K to ~8K tokens (76% reduction)
- Cold start improved from 4+ minutes to 30–45 seconds
- All skills remain available as slash commands
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

## Field Notes

### 2026-04-13: Strip counts from ADRs — they drift silently
ADR-034 originally stated "all 25 skills use the stub pattern." By 2026-04-13 the actual count was 27 (cargo-machete, mcp-builder, rust-skills added post-ADR). The count was discovered during a reconcile consistency scan — not immediately obvious. Fix: remove the count entirely. Write "all skills use the stub pattern" (decision-level) and link to `docs/reference/skills.md` (auto-generated, always current). Rule: ADRs capture decisions, not inventory state. Counts belong in generated references only.
Source: /brana:reconcile 2026-04-13
