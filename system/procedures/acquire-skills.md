
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

Scan all SKILL.md files in the plugin's `system/skills/` directory:

```bash
for d in system/skills/*/; do
    [ -f "$d/SKILL.md" ] || continue
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
- options: ["All gaps (Recommended)", "Pick which ones", "Skip"]

If "Skip": report and exit.
If "Pick which ones": let user select from gap list.

### Step 3: Search — Query marketplaces

Search for each gap keyword using the first available source:

**Tier 1a: Vercel skills CLI** (check: `npx skills --version 2>/dev/null`)
```bash
# Keyword search — use `find`, not `search` (search outputs logo only, no results)
npx skills find "<keyword>" 2>/dev/null

# Enumerate skills from known orgs via --list flag
for org in anthropics vercel-labs trailofbits supabase redis fastapi; do
  npx skills add "$org" --list 2>/dev/null
done
```

**Tier 1b: skills.sh** (always available via WebFetch)
```
WebFetch: https://skills.sh
```
Parse the official skills directory for keyword matches. Results here are **Verified** trust tier (see Step 3b).

**Tier 2: WebSearch** (fallback if Tier 1 yields no results)
```
WebSearch: "SKILL.md <keyword> site:github.com claude"
```

For each search result, collect:
- Skill name and author
- Description (first 1-2 sentences)
- Source (npm package, GitHub repo URL, or skills.sh listing)
- Install count or stars (if available)

Report which search tier is active:
```
Searching via: Vercel skills CLI + skills.sh
```
or:
```
Searching via: skills.sh + web (install `npx skills` for CLI results)
```

### Step 3b: Classify source trust tier

Each search result is classified by its source into a trust tier. The tier determines
install behavior (step 5) and tool access for the installed skill.

| Source | Trust tier | Install behavior | Tool access |
|--------|-----------|-----------------|-------------|
| `github.com/anthropics/*` | **Trusted** | Auto-install with confirmation | Full (all tools) |
| `skills.sh` official section, `trailofbits/*` | **Verified** | Install with review prompt | Default set |
| Other GitHub repos, npm packages | **Community** | Quarantine — install with read-only tools | Read, Glob, Grep only |
| Unknown URL, no source info | **Blocked** | Reject — user must add source first | N/A |

**Classification logic:**
```
if source URL contains "github.com/anthropics" → trusted
elif source marked "official" on skills.sh OR author in verified-authors list → verified
elif source is a GitHub repo or npm package → community
else → blocked (skip candidate, warn user)
```

**Verified authors list** (extend as trust is established):
`anthropics`, `trailofbits`, `vercel-labs`, `slavingia`

Display the trust tier next to each candidate in step 4:
```
  1. @anthropics/skills/cloudflare [TRUSTED]
  2. @secondsky/cloudflare-deploy [COMMUNITY — quarantine]
```

### Step 4: Evaluate and present

For each candidate, if possible fetch the SKILL.md content:
- CLI: `npx skills info <package>` or `npx skills cat <package>`
- Web: `WebFetch` the raw SKILL.md from GitHub

**Safety scan** (discard if any trigger):
- Empty or under 100 characters
- Contains `rm -rf`, `sudo`, `curl | sh`, `eval(`, or similar dangerous patterns
- No description or purpose statement
- **Blocked** trust tier (unknown source — reject entirely)

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

### Step 5: Install (trust-tier-aware)

For each selected skill:

**1. Get the SKILL.md content:**
- CLI: `npx skills add <package> --dir /tmp/skill-staging/` then read the file
- Web: already fetched in Step 4, use that content

**2. Apply trust-tier restrictions before saving:**

| Trust tier | Action |
|-----------|--------|
| **Trusted** | Install as-is. Full allowed-tools preserved. |
| **Verified** | Install. Keep existing allowed-tools but warn if `Bash` is unrestricted. |
| **Community** | Quarantine: rewrite `allowed-tools` to read-only set (`Read`, `Glob`, `Grep`, `AskUserQuestion`). Add `quarantine: true` to frontmatter. User can promote later via `/brana:reconcile`. |
| **Blocked** | Should not reach here (rejected in step 4). |

For quarantine installs, inform user:
```
Installed in quarantine mode (read-only tools).
Run /brana:reconcile --scope security to review and promote to full access.
```

**3. Install as universal stub (per ADR-034):**

Write the procedure body to `system/procedures/<skill-name>.md`:
```bash
# Write the full SKILL.md content as a procedure file
Write: system/procedures/<skill-name>.md ← full skill content
```

Write a stub to `system/skills/<skill-name>/SKILL.md`:
```yaml
---
name: <skill-name>
description: "<description from source>"
group: brana
keywords: [<extracted keywords>]
allowed-tools: [<per trust tier>]
status: acquired
source: "<source URL>"
acquired: "<YYYY-MM-DD>"
quarantine: <true if community tier>
---

<!-- PROCEDURE_FILE: procedures/<skill-name>.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/<skill-name>.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/<skill-name>.md`.
```

**Frontmatter fixup** — marketplace skills often lack these fields. Always add:
- `group: brana` (required for plugin discovery)
- `status: acquired` (distinguishes from native skills)
- `allowed-tools` (per trust tier — community gets read-only set)
- `source` and `acquired` (provenance tracking)

**4. Index in ruflo (best-effort):**

```bash
brana skills reindex
```

This indexes the new skill's frontmatter into ruflo's `skills` namespace, making it discoverable by `/brana:backlog start` skill routing and `/brana:do`. If CLI unavailable, skip — next session start will reindex.

### Step 6: Report

```
Acquired 2 skills:

  + cloudflare-workers-deploy (npm, @secondsky) → system/skills/ + system/procedures/
  + prisma-orm (npm, @vercel-labs) → system/skills/ + system/procedures/

  Not found (general knowledge):
    stripe, redis

  Indexed in ruflo: yes
  Available as: /brana:cloudflare-workers-deploy, /brana:prisma-orm
```

## Notes

- Acquired skills follow the universal stub model (ADR-034): stub in `system/skills/`, procedure body in `system/procedures/`. Git-tracked like native skills.
- If no marketplace CLI is installed, WebSearch finds GitHub repos with SKILL.md files. Lower quality but always works.
- Never auto-install. Always present candidates and let the user choose.
- If a skill turns out to be low quality after use, delete the stub and procedure file.
