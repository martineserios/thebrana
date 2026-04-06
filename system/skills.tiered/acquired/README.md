# Acquired Skills

This directory stores third-party skills installed via `/brana:acquire-skills`.

When the acquire-skills workflow finds and installs a skill from a marketplace or GitHub, it saves the skill here as `<skill-name>/SKILL.md`. These are version-controlled so they persist across deploys and sessions.

## How skills get here

1. `/brana:acquire-skills` scans a project for tech gaps
2. It searches marketplaces (Vercel skills CLI, GitHub) for matching skills
3. You select which candidates to install
4. Selected skills are saved here and activated in `~/.claude/skills/`

## Managing acquired skills

- **Remove a skill**: delete its directory here and redeploy
- **Update a skill**: re-run `/brana:acquire-skills` -- it will find newer versions
- **List installed skills**: check the `## Acquired` section in `docs/guide/skills.md`

## Why `.gitkeep`?

Git doesn't track empty directories. The `.gitkeep` file ensures this directory exists in fresh clones before any skills are acquired.
