# ADR-012: Acquire Skills — Manual Skill Discovery and Installation

**Date:** 2026-03-05
**Status:** accepted
**Task:** t-206

## Context

Brana has 39 custom skills covering core workflows. When working on projects with unfamiliar tech (Cloudflare Workers, Prisma, tRPC), no matching skill exists. External skill marketplaces have matured (Vercel skills, SkillHub, SkillsMP) with thousands of community skills following the SKILL.md standard.

An automated version was proposed and rejected via challenger review — it builds package-manager infrastructure for events that happen 2-3 times per quarter. The lean alternative: a manual command the user runs when they need it.

## Decision

Build `/acquire-skills` as a skill (SKILL.md) with three-tier marketplace search:

1. **SkillHub MCP** (if configured) — structured JSON, AI quality scores
2. **Vercel skills CLI** (if installed) — `npx skills search`, npm ecosystem
3. **WebSearch** (always available) — GitHub repos with SKILL.md files

The skill scans project context (package.json, Dockerfile, CLAUDE.md, tasks.json), diffs against local skills, searches for gaps, presents candidates, and installs user-approved skills to `system/skills/acquired/`.

Key design choices:
- **Manual trigger only** — no auto-detection, no hooks. User runs `/acquire-skills` when they need it.
- **User approves everything** — candidates presented with quality info, user picks which to install.
- **Version-controlled** — acquired skills saved to `system/skills/acquired/<name>/`, deployed via existing deploy.sh pipeline.
- **Single catalog** — `skill-catalog.md` updated with acquired entries. No new registry files.
- **No deploy.sh changes** — `acquired/` is inside `skills/`, already in the copy path.

## Consequences

- **Easier:** entering new projects with unfamiliar stacks. One command finds relevant skills.
- **Easier:** skill catalog grows organically from actual work, not speculation.
- **Harder:** nothing significant — complexity is contained in one SKILL.md file.
- **Risk:** marketplace skill quality varies. Mitigated by user review before install and safety scan (empty content, dangerous tools).
