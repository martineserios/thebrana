# Feature: Acquire Skills

**Date:** 2026-03-05
**Status:** designing

## Goal

A manual command (`/brana:acquire-skills`) that scans a project's tech stack, identifies skill gaps against locally installed skills, searches marketplaces for matching skills, and installs user-approved ones permanently.

## Audience

The brana operator (me) — when entering a new project, picking up unfamiliar tech, or periodically refreshing skill coverage.

## Constraints

- Must be a skill (SKILL.md), not infrastructure
- No deploy.sh changes — `system/skills/acquired/` is inside `skills/`, already deployed
- No auto-install — user approves every skill
- No lifecycle automation — no auto-removal, no promotion logic
- Single source of truth — `skill-catalog.md` gets updated, no new registry files
- Graceful degradation — works with just WebSearch if no MCP or CLI available

## Scope (v1)

- Scan project for tech signals (package.json, Dockerfile, CLAUDE.md, tasks.json)
- Diff against local skill names + descriptions
- Search 3 tiers: SkillHub MCP > Vercel skills CLI > WebSearch
- Present candidates with quality info, let user pick
- Install to `system/skills/acquired/<name>/` + `~/.claude/skills/`
- Update `skill-catalog.md` with acquired entry
- Three input modes: project scan, task-id scan, direct keyword

## Deferred

- Auto-trigger on `/brana:backlog pick` (premature — no evidence of frequency)
- Quality scoring beyond marketplace-provided scores
- Lifecycle management (usage-based promotion/removal)
- Skill update checking (version drift)
- SkillHub MCP setup (evaluate when actually needed)

## Research findings

- **Vercel skills** (`npx skills`): open ecosystem, npm-based, supports 42 agents, `npx skills search` + `npx skills add`. Snyk security scanning. Most mature CLI.
- **SkillHub**: MCP server available (`@skillhub/mcp-server`), 7K+ AI-evaluated skills (S/A/B/C ranks), requires API key.
- **SkillsMP**: 350K+ skills aggregated from GitHub, `agent-skills-cli` with FZF interactive search.
- **aitmpl**: 400+ curated components (agents, commands, hooks, MCPs, skills), `npx claude-code-templates`.
- **Challenger verdict:** automated version overengineered. Manual command achieves 90% of value at 10% complexity.

## Design

See ADR-012. Three-tier search with graceful degradation. Skill installed to `system/skills/acquired/`, catalog updated, immediate activation via copy to `~/.claude/skills/`.

## Open questions

- Which marketplace produces best results in practice? (will learn through usage)
- Should acquired skills be .gitignored or version-controlled? (v1: version-controlled)
