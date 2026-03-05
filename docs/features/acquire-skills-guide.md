# Feature: Acquire Skills — User Guide

**Task:** [t-206](../../.claude/tasks.json)
**Status:** implemented (2026-03-05)
**ADR:** [ADR-012](../decisions/ADR-012-acquire-skills.md)

---

## What It Does (Plain English)

When you start working on a project that uses tech you don't have skills for — say Cloudflare Workers, Prisma, or Stripe — you can run `/acquire-skills` and the system will:

1. Look at your project's files to figure out what tech it uses
2. Compare that against the skills you already have
3. Search online marketplaces for skills that fill the gaps
4. Show you what it found and let you pick which ones to install
5. Save them permanently so they're there next time

You run it once when entering a new project or picking up unfamiliar tech. After that, the skills are part of your system.

## How to Use It

Three ways to invoke:

```
/acquire-skills                    — scan the current project
/acquire-skills t-045              — scan what a specific task needs
/acquire-skills cloudflare         — search directly for a keyword
```

### Example Session

```
> /acquire-skills

Scanning project: nexeye_eyedetect

Tech detected: python, fastapi, docker, onnx, cloudflare-workers,
               tailscale, hetzner, github-actions

Already covered by local skills:
  docker → (general knowledge)
  github-actions → (general knowledge)

Gaps (no matching skill):
  cloudflare-workers, fastapi, onnx, tailscale, hetzner

Search marketplaces for these gaps?
  [All gaps] [Pick which ones] [Skip]

> All gaps

Searching via: web (install `npx skills` for better results)

cloudflare-workers (1 candidate):
  1. @anthropics/skills/cloudflare
     "Cloudflare Workers and Pages deployment patterns..."
     Source: github.com/anthropics/skills

fastapi (2 candidates):
  1. @vercel-labs/fastapi
     "FastAPI patterns, Pydantic models, async endpoints..."
     Source: github.com/vercel-labs/skills
  2. @community/fastapi-advanced
     "Advanced FastAPI: middleware, dependencies, testing..."
     Source: github.com/community/agent-skills

onnx, tailscale, hetzner: no skills found

Which skills to install?
  [x] @anthropics/skills/cloudflare
  [x] @vercel-labs/fastapi
  [ ] @community/fastapi-advanced
  [ ] Skip all

Acquired 2 skills:
  + cloudflare (GitHub, @anthropics)
  + fastapi (GitHub, @vercel-labs)

  Updated: docs/guide/skills.md
  Active in: ~/.claude/skills/ (this session)
  Persisted: system/skills/acquired/ (git tracked)

  Run deploy.sh to make permanent across sessions.
```

## How It Works (Technical)

### Project Scanning

The skill reads these files to detect tech keywords:

```
package.json           → dependency names (express, prisma, stripe...)
requirements.txt       → python packages (fastapi, celery, sqlalchemy...)
pyproject.toml         → python packages from [project.dependencies]
Dockerfile             → FROM images (node:20, python:3.12, nginx...)
docker-compose.yml     → service names and images
.tool-versions         → runtime names (nodejs, python, ruby...)
CLAUDE.md              → stack keywords from project description
.claude/tasks.json     → tags from pending/in_progress tasks
```

Keywords are deduplicated and lowercased. The scan is best-effort — missing files are skipped silently.

### Gap Detection

For each keyword, the skill checks all local SKILL.md files:

```
~/.claude/skills/
├── tasks/SKILL.md          → description mentions "tasks, plan, track"
├── gsheets/SKILL.md        → description mentions "google sheets, MCP"
├── research/SKILL.md       → description mentions "research, topic"
...
```

A keyword matches if it appears in the skill's directory name or description. Unmatched keywords are "gaps."

### Three-Tier Search

```
TIER 1: Vercel skills CLI (if installed)
        npx skills search "<keyword>"
        Best results — npm ecosystem, structured output
        Install: npm install -g skills

TIER 2: WebSearch (always available)
        "SKILL.md <keyword> site:github.com claude"
        Lower quality but works everywhere
        No install needed

(Future) TIER 3: SkillHub MCP (if configured)
        search_skills MCP tool call
        Structured JSON with AI quality scores
        Needs API key setup
```

The skill auto-detects which tier is available and reports it.

### Safety Scan

Before presenting a candidate, the skill checks:

- Is the SKILL.md empty or under 100 characters? → discard
- Does it contain `rm -rf`, `sudo`, `curl | sh`, `eval(`? → flag as risky
- Does it have a clear description? → required

Dangerous skills are flagged but not auto-rejected — you decide.

### Install Flow

```
User approves a skill
       │
       ├── 1. Write SKILL.md to system/skills/acquired/<name>/
       │      (version controlled in git)
       │
       ├── 2. Copy to ~/.claude/skills/<name>/
       │      (active immediately, no deploy needed)
       │
       └── 3. Append to docs/guide/skills.md "Acquired" section
              (single source of truth for all skills)
```

### File Layout After Acquisition

```
system/skills/
├── tasks/SKILL.md              ← brana-native (40 existing)
├── research/SKILL.md
├── acquire-skills/SKILL.md     ← this skill
│   ...
└── acquired/                    ← marketplace skills
    ├── cloudflare/
    │   └── SKILL.md
    └── fastapi/
        └── SKILL.md
```

`deploy.sh` copies everything in `system/skills/` to `~/.claude/skills/`, including `acquired/` subdirectories. No deploy.sh changes needed.

## Better Results with Vercel Skills CLI

The web search tier works but produces noisier results. For better skill discovery, install the Vercel skills CLI:

```bash
npm install -g skills
```

This gives `/acquire-skills` access to a structured npm-based skill ecosystem with thousands of community skills. The skill auto-detects the CLI and uses it as the primary search source.

## Removing Acquired Skills

If a skill turns out to be low quality:

```bash
rm -rf system/skills/acquired/<name>/
rm -rf ~/.claude/skills/<name>/
# Edit docs/guide/skills.md to remove the entry
# Commit and deploy
```

## What This Doesn't Do

- **No auto-trigger** — you run it when you need it
- **No auto-install** — always asks before installing anything
- **No auto-removal** — you decide what stays
- **No version tracking** — skills are snapshots, not auto-updated
- **No quality scoring** — you review the SKILL.md content yourself

These are intentional design choices. See [ADR-012](../decisions/ADR-012-acquire-skills.md) for rationale.
