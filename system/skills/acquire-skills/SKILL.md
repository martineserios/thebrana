---
name: acquire-skills
description: "Find and install skills for project tech gaps. Use when entering a project with unfamiliar tech or when no local skill matches a task context."
effort: low
keywords: [skills, marketplace, install, gap, discovery, external]
task_strategies: [feature, spike]
stream_affinity: [roadmap, tech-debt]
group: brana
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Grep
  - WebSearch
  - WebFetch
  - AskUserQuestion
  - Agent
status: stable
growth_stage: evergreen
---

# Acquire Skills

Scan project context, identify missing skills, search external marketplaces, install what you approve.

## Usage

```
/brana:acquire-skills                    — scan current project
/brana:acquire-skills <task-id>          — scan a specific task's needs
/brana:acquire-skills <keyword>          — direct search ("cloudflare")
```

## Process

### Step 1: Gather — Read project signals

Detect the input mode from the argument:

- **No argument:** scan project from CWD
- **Task ID (t-NNN):** read that task from `.claude/tasks.json`, extract tags + description
- **Keyword:** skip scan, use keyword directly in Step 3

For project scan, read these files (skip missing ones silently):

| File | Extract |
|------|---------|
| `package.json` | `dependencies` + `devDependencies` keys |
| `requirements.txt` / `pyproject.toml` | package names |
| `Dockerfile` / `docker-compose.yml` | `FROM` images, service names |
| `.tool-versions` / `.nvmrc` | runtime names |
| `CLAUDE.md` / `.claude/CLAUDE.md` | stack keywords from description |
| `.claude/tasks.json` | tags from all `pending` + `in_progress` tasks |

Collect into a flat list of **tech keywords** (deduplicated, lowercased).

Example output:
```
Tech detected: next.js, prisma, postgres, tailwind, cloudflare-workers,
               docker, redis, stripe
```

### Step 2: Diff — Compare against local skills

Scan all SKILL.md files in `~/.claude/skills/`:

```bash
for d in ~/.claude/skills/*/; do
    name=$(basename "$d")
    desc=$(head -10 "$d/SKILL.md" 2>/dev/null | grep -m1 "^description:" | sed 's/^description: *"//' | sed 's/"$//')
    echo "$name: $desc"
done
```

For each tech keyword, check if any local skill name or description contains it.

Present the diff:

```
Already covered:
  docker → (general knowledge, no dedicated skill)
  postgres → gsheets (partial, queries only)

Gaps (no matching skill):
  cloudflare-workers, prisma, stripe, redis
```

Use **AskUserQuestion** to confirm:
- question: "Search marketplaces for these gaps?"
- options: ["All gaps", "Pick which ones", "Skip"]

If "Skip": report and exit.
If "Pick which ones": let user select from gap list.

### Step 3: Search — Query marketplaces

Search for each gap keyword using the first available source:

**Tier 1: Vercel skills CLI** (check: `npx skills --version 2>/dev/null`)
```bash
npx skills search "<keyword>" 2>/dev/null
```

**Tier 2: WebSearch** (always available)
```
WebSearch: "SKILL.md <keyword> site:github.com claude"
```

For each search result, collect:
- Skill name and author
- Description (first 1-2 sentences)
- Source (npm package, GitHub repo URL)
- Install count or stars (if available)

Report which search tier is active:
```
Searching via: Vercel skills CLI
```
or:
```
Searching via: web (install `npx skills` for better results)
```

### Step 4: Evaluate and present

For each candidate, if possible fetch the SKILL.md content:
- CLI: `npx skills info <package>` or `npx skills cat <package>`
- Web: `WebFetch` the raw SKILL.md from GitHub

**Safety scan** (discard if any trigger):
- Empty or under 100 characters
- Contains `rm -rf`, `sudo`, `curl | sh`, `eval(`, or similar dangerous patterns
- No description or purpose statement

Present grouped by gap:

```
cloudflare-workers (2 candidates):

  1. @anthropics/skills/cloudflare
     "Cloudflare Workers and Pages deployment patterns..."
     Source: github.com/anthropics/skills · official

  2. @secondsky/cloudflare-workers-deploy
     "Production deployment, wrangler config, D1 bindings..."
     Source: npm:@secondsky/cloudflare-workers-deploy · 2.1K installs

prisma (1 candidate):

  1. @vercel-labs/prisma-orm
     "Prisma ORM — schema design, migrations, queries..."
     Source: npm:@vercel-labs/prisma-orm · 8.4K installs

stripe, redis: no skills found (Claude will use general knowledge)
```

Use **AskUserQuestion** (multiSelect: true):
- question: "Which skills to install?"
- options: one per candidate + "Skip all"

### Step 5: Install

For each selected skill:

**1. Get the SKILL.md content:**
- CLI: `npx skills add <package> --dir /tmp/skill-staging/` then read the file
- Web: already fetched in Step 4, use that content

**2. Save to system/skills/acquired/:**

```bash
mkdir -p system/skills/acquired/<skill-name>/
```

Write SKILL.md to `system/skills/acquired/<skill-name>/SKILL.md`.

**3. Activate immediately:**

```bash
mkdir -p ~/.claude/skills/<skill-name>/
cp system/skills/acquired/<skill-name>/SKILL.md ~/.claude/skills/<skill-name>/SKILL.md
```

**4. Update skill-catalog.md:**

Append to the `## Acquired` section of `docs/guide/skills.md`:

```markdown
### `<skill-name>` (acquired)
{description} — Source: {source}. Acquired {YYYY-MM-DD} for {project/task context}.
```

If the `## Acquired` section doesn't exist, create it at the end of the file.

### Step 6: Report

```
Acquired 2 skills:

  + cloudflare-workers-deploy (npm, @secondsky)
  + prisma-orm (npm, @vercel-labs)

  Not found (general knowledge):
    stripe, redis

  Updated: docs/guide/skills.md
  Active in: ~/.claude/skills/ (this session)
  Persisted: system/skills/acquired/ (git tracked)

  Run deploy.sh to make permanent across sessions.
```

## Notes

- Acquired skills are version-controlled in `system/skills/acquired/`. They survive `deploy.sh` like native skills.
- If no marketplace CLI is installed, WebSearch finds GitHub repos with SKILL.md files. Lower quality but always works.
- Never auto-install. Always present candidates and let the user choose.
- If a skill turns out to be low quality after use, delete it from `system/skills/acquired/` and redeploy.
