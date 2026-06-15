---
name: acquire-skills
description: "Find and install skills for what you're doing — tech stack AND thinking/reasoning gaps. Analyzes activity type (deciding, strategizing, challenging, analyzing, planning) and tech context to surface relevant skills. Use when entering unfamiliar tech, stuck on a reasoning challenge, or when no local skill covers the current task."
effort: low
model: haiku
keywords: [skills, marketplace, install, gap, discovery, external, reasoning, frameworks, thinking]
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

Find and install skills for the current task — across both tech and thinking/reasoning dimensions.

## Usage

```
/brana:acquire-skills                    — scan current activity + project
/brana:acquire-skills <task-id>          — scan a specific task's needs
/brana:acquire-skills <keyword>          — direct search ("cloudflare", "decision matrix")
```

## Never suggest these (brana workflow internals)

The following skills are system workflow tools, not capability skills. Never surface them as recommendations:
`build`, `backlog`, `close`, `sitrep`, `onboard`, `align`, `reconcile`, `ship`, `docs`,
`retrospective`, `review`, `gemini`, `claudemd`, `plugin`, `scheduler`, `do`, `log`,
`export-pdf`, `verify-docs`, `client-retire`, `cargo-machete`, `bash-defensive-patterns`,
`rust-skills`, `gsheets`, `meta-templates`, `mcp-builder`, `memory`, `discover`.

Thinking skills ARE valid to recommend: `decide`, `brainstorm`, `challenge`, `swot-analysis`,
`decision-matrix`, `critical-thinking-logical-reasoning`, `pre-mortem`, `inversion`,
`first-principles`, `second-order-thinking`, `six-thinking-hats`, `systems-thinking`,
`jobs-to-be-done`.

## Process

### Step 0: Detect mode

From `$ARGUMENTS`:
- **No argument:** run Steps 1a + 1b (activity detection + tech scan)
- **Task ID (t-NNN):** read task from `.claude/tasks.json`, extract subject + tags + description → use as context for both Steps 1a and 1b
- **Keyword:** skip Steps 1a + 1b entirely, use keyword directly in Step 3

---

### Step 1a: Detect activity type

Read the current conversation context (recent turns) and any task/argument provided.

Classify the primary activity the user is doing right now:

| Activity | Signals | Relevant thinking skills |
|----------|---------|--------------------------|
| **Deciding** | "should I", "A or B", "which option", "choose between" | `decide`, `decision-matrix`, `six-thinking-hats` |
| **Strategizing** | "market", "competitive", "direction", "positioning", "business model" | `swot-analysis`, `systems-thinking`, `second-order-thinking`, `scenario-planning` |
| **Analyzing problem** | "why is", "root cause", "debug", "understand", "what caused" | `critical-thinking-logical-reasoning`, `first-principles`, `systems-thinking` |
| **Challenging / stress-testing** | "risk", "what could go wrong", "is this right", "review this plan" | `challenge`, `pre-mortem`, `inversion`, `critical-thinking-logical-reasoning` |
| **Ideating / exploring** | "idea", "what if", "explore", "brainstorm", "new approach" | `brainstorm`, `first-principles`, `jobs-to-be-done`, `second-order-thinking` |
| **Planning** | "how to approach", "phases", "roadmap", "before starting" | `pre-mortem`, `second-order-thinking`, `systems-thinking` |
| **Researching** | "learn about", "understand", "how does X work" | `critical-thinking-logical-reasoning`, `systems-thinking`, `jobs-to-be-done` |
| **Building** | implementation, coding, writing features | tech skills only (Step 1b) |

If activity is **Building only** → thinking skills aren't the gap, skip to Step 1b.
Otherwise → note the detected activity and the recommended thinking skills. These surface in Step 2 as "thinking gaps" even if they're already installed (they may not be well-known).

---

### Step 1b: Gather tech signals

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

---

### Step 2: Surface gaps

Scan local skills:

```bash
for d in system/skills/*/; do
    [ -f "$d/SKILL.md" ] || continue
    name=$(basename "$d")
    desc=$(head -10 "$d/SKILL.md" 2>/dev/null | grep -m1 "^description:" | sed 's/^description: *"//' | sed 's/"$//')
    group=$(head -10 "$d/SKILL.md" 2>/dev/null | grep -m1 "^group:" | sed 's/^group: *//')
    echo "$name|$desc|$group"
done
```

**Thinking gaps (from Step 1a):**
For each recommended thinking skill:
- If already installed locally → show as "available" (might not be well-known to user)
- If not installed → show as "gap"

Always present the thinking skills relevant to the detected activity — even installed ones. The user may not know they exist.

**Tech gaps (from Step 1b):**
For each tech keyword, check if any local skill name or description contains it.

Present in two sections:

```
Activity detected: [Deciding / Strategizing / ...]

Thinking skills for this activity:
  ✓ decision-matrix    (installed) — weighted scoring of alternatives
  ✓ six-thinking-hats  (installed) — 6-perspective parallel analysis
  ✗ scenario-planning              (not installed) — 3-4 plausible futures

Tech stack: next.js, prisma, postgres, tailwind

Tech gaps (no local skill):
  prisma, cloudflare-workers
```

Ask:

```
AskUserQuestion:
  question: "What should we look for?"
  options:
    - "Thinking skills for [detected activity] (Recommended if not well-known)"
    - "Tech gaps: [gap list]"
    - "Both"
    - "Skip"
```

---

### Step 3: Search marketplaces

Search for each gap keyword using the first available source:

**Tier 1a: Vercel skills CLI** (check: `npx skills --version 2>/dev/null`)
```bash
npx skills find "<keyword>" 2>/dev/null
```

**Tier 1b: skills.sh** (always available via WebFetch — results here are Verified tier)
```
WebFetch: https://skills.sh
```

**Tier 2: WebSearch** (fallback if Tier 1 yields nothing)
```
WebSearch: "SKILL.md <keyword> site:github.com claude"
```

For thinking skill gaps, search terms to use:
- `decision matrix`, `pre-mortem`, `inversion thinking`, `first principles`, `SWOT`, `jobs to be done`, `systems thinking`, `second order thinking`, `six thinking hats`

---

### Step 3b: Trust tier classification

| Source | Trust tier | Install behavior |
|--------|-----------|-----------------|
| `github.com/anthropics/*` | **Trusted** | Auto-install with confirmation |
| `skills.sh` official, `trailofbits/*` | **Verified** | Install with review prompt |
| Other GitHub repos, npm packages | **Community** | Quarantine — read-only tools |
| Unknown URL, no source info | **Blocked** | Reject |

**Verified authors:** `anthropics`, `trailofbits`, `vercel-labs`, `slavingia`

---

### Step 4: Evaluate and present

For each candidate, fetch the SKILL.md content:
- CLI: `npx skills add <package>` (stages to `.agents/skills/`)
- Web: `WebFetch` the raw SKILL.md from GitHub

**Safety scan** (discard if any trigger):
- Empty or under 100 characters
- Contains `rm -rf`, `sudo`, `curl | sh`, `eval(`
- No description or purpose statement
- **Blocked** trust tier

Present grouped by gap, with trust tier shown:

```
Thinking — deciding:

  (already installed — may be useful now)
  ✓ decision-matrix     "Compare alternatives with weighted criteria..."
  ✓ six-thinking-hats   "6 perspectives: facts, risks, benefits, creativity..."

  (not installed)
  1. andurilcode/skills@scenario-planning [COMMUNITY]
     "Build 3-4 plausible futures, stress-test strategy against each..."

Tech — prisma:

  1. @vercel-labs/prisma-orm [VERIFIED]
     "Prisma ORM — schema design, migrations, queries..."
```

AskUserQuestion (multiSelect):
- question: "Which skills to install? (Installed ones are shown for awareness only)"
- options: one per NOT-INSTALLED candidate + "Skip all"

---

### Step 5: Install (trust-tier-aware)

For each selected skill:

**1. Get the SKILL.md content** from `.agents/skills/` (staged by CLI) or fetched in Step 4.

**2. Apply trust-tier restrictions:**

| Trust tier | Action |
|-----------|--------|
| **Trusted** | Install as-is. |
| **Verified** | Install. Warn if `Bash` is unrestricted. |
| **Community** | Quarantine: rewrite `allowed-tools` to `[Read, Glob, Grep, AskUserQuestion]`. Add `quarantine: true`. |
| **Blocked** | Reject (never reaches here). |

**3. Write to `system/skills/<skill-name>/SKILL.md`** with brana frontmatter:

```yaml
---
name: <skill-name>
description: "<description from source>"
group: thinking          # or appropriate group
keywords: [<extracted keywords>]
allowed-tools: [<per trust tier>]
status: acquired
source: "<source URL>"
acquired: "<YYYY-MM-DD>"
quarantine: <true if community tier>
---

<full procedure body from source>
```

Always add: `group`, `status: acquired`, `allowed-tools`, `source`, `acquired`.

**4. Reindex:**
```bash
brana skills reindex
```

---

### Step 6: Report

```
Activity: [detected type]

Thinking skills available for this activity:
  ✓ decision-matrix, six-thinking-hats (already installed)
  + scenario-planning (just installed)

Tech:
  + prisma-orm (installed)
  - stripe (not found — Claude will use general knowledge)

Total: [N] skills now available for [activity type]
```

## Notes

- Never auto-install. Always present and let the user choose.
- Installed thinking skills are always shown for awareness even if already present — the user may not know what's available.
- Thinking skills can be suggested even without keyword arguments — activity detection from conversation context is enough.
- If a skill turns out to be low quality after use, delete the skill directory.
- Acquired skills follow inline model (ADR-034 amendment, t-1941): full body in `system/skills/<name>/SKILL.md`.
