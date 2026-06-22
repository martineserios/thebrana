---
name: onboard
description: "Scan and diagnose a project, or scaffold a new client from scratch. Works for code and venture clients. Auto-detects project type."
effort: medium
model: haiku
keywords: [scan, diagnose, project, structure, tech-stack, gaps, scaffold, new-client]
task_strategies: [investigation, greenfield]
stream_affinity: [roadmap]
argument-hint: "[new [slug] | project-path]"
group: execution
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - Write
  - Edit
  - AskUserQuestion
  - Task
  - TaskList
  - Skill
status: stable
growth_stage: evergreen
---
# Onboard — Project Discovery & Scaffolding

Two modes:
- **Scan** (default): Diagnostic entry point for an existing project.
- **New**: Scaffold a new client from scratch, then hand off to `/brana:align`.

## When to use

- **Scan:** First session on a new project, taking over an existing project, or periodic health check.
- **New:** Starting a brand new client — creates the directory, git repo, portfolio entry, then delegates to align for structure.

## Subcommand routing

Parse the first argument:
- `new` or `new <slug>` → run the **New Client** flow below
- Anything else (path, no argument) → run the **Scan** flow (existing behavior)

---

# /brana:onboard new — New Client Scaffolding

Thin wrapper: collect inputs → create bare directory + git → register → delegate to `/brana:align`.

**No templates, no type-aware scaffolding here.** Align owns that.

## Step Registry (new)

Register these steps: COLLECT, GUARD, CREATE, REGISTER, ALIGN.

---

## Step 1: COLLECT

Gather the minimum needed to create the project root.

### Required
- **slug** — from argument or prompt. Lowercase, hyphens ok, no spaces. This becomes the directory name.

### Interactive (AskUserQuestion, batch into 1-2 calls)

| Field | Prompt | Options | Default |
|-------|--------|---------|---------|
| display_name | "Display name?" | free text | titlecase of slug |
| type | "Project type?" | code / venture / hybrid | code |
| description | "One-line description?" | free text | — |
| category | "Category?" | client (paid work — Recommended for new client projects) / venture (your IP — side project, learning, monetizing) / personal | client |
| base_path | "Location?" | auto from category: `clients/` / `ventures/` / `personal/` (all under `~/enter_thebrana/`) / custom path | auto |
| github | "Create GitHub remote?" | yes / no | no |
| github_org | (only if github=yes) "GitHub org?" | martineserios / other | martineserios |
| github_visibility | (only if github=yes) "Visibility?" | private (Recommended) / public | private |

### Flag overrides (skip prompts)

```
/brana:onboard new myproject --type venture --category venture --github --org myorg
/brana:onboard new myclient --type code --category client
```

Any flag provided skips that prompt.

### Category → base_path mapping

| Category | base_path |
|----------|-----------|
| client | `~/enter_thebrana/clients/` |
| venture | `~/enter_thebrana/ventures/` |
| personal | `~/enter_thebrana/personal/` |

Custom `--path` overrides category mapping.

---

## Step 2: GUARD

Before creating anything, check for conflicts:

```bash
# Check directory doesn't exist
[ -d "{base_path}/{slug}" ] && echo "ERROR: Directory already exists" && exit 1

# Check portfolio for duplicate slug
grep -q "### {slug}" ~/.claude/memory/portfolio.md && echo "WARN: Already in portfolio"
```

- **Directory exists:** Abort. Suggest `/brana:onboard` (scan) or `/brana:align` instead.
- **Portfolio entry exists but no directory:** Ask — "Portfolio entry found but no directory. Continue creating?" (this handles the case where someone added a portfolio entry early, like prof_man)

---

## Step 3: CREATE

### Create bare root + git

```bash
mkdir -p "{base_path}/{slug}"
cd "{base_path}/{slug}"
git init
```

### Create minimal seed files

Only files that align does NOT create (or that align needs to exist before it runs):

```bash
# CLAUDE.md stub — align will merge into this
cat > CLAUDE.md << 'EOF'
# {display_name}

{description}
EOF

# Empty .claude dir structure that align expects
mkdir -p .claude/memory .claude/rules
echo "# Memory Index — {slug}" > .claude/memory/MEMORY.md

# Inbox for unstructured input (files, screenshots, references)
# Contents gitignored — only the directory and .gitignore are tracked
mkdir -p inbox
cat > inbox/.gitignore << 'GITIGNORE'
# Ignore everything in inbox except this file
*
!.gitignore
GITIGNORE
```

### Initial commit

```bash
git add -A
git commit -m "chore: scaffold {slug}"
```

### GitHub remote (if requested)

```bash
gh repo create {github_org}/{slug} --{visibility} --source . --push
```

If `gh` fails (not installed, not authenticated): warn and continue. The project is usable without a remote.

---

## Step 4: REGISTER

### Portfolio entry

Append to `~/.claude/memory/portfolio.md` under the matching section:
- category=client → `## Clients (paid work — external stakeholder)`
- category=venture → `## Ventures (your IP — side projects, learning, monetizing)`
- category=personal → `## Personal (personal OS — not a project)`

```markdown
### {slug}
- **Type:** {type} — {description}
- **Location:** `~/enter_thebrana/{category_dir}/{slug}/`
- **Status:** Starting — {today}
```

If the slug already has a portfolio entry (detected in GUARD), update it instead of duplicating.

### Project memory directory

```bash
# Create the Claude Code project memory dir
# Path convention: dash-separated full path
MEMORY_DIR="$HOME/.claude/projects/-home-martineserios-enter-thebrana-clients-{slug}/memory"
mkdir -p "$MEMORY_DIR"
echo "# Memory Index — {slug}" > "$MEMORY_DIR/MEMORY.md"
```

---

## Step 5: ALIGN

Delegate to `/brana:align` for all structure scaffolding:

```
Skill(skill="brana:align", args="{base_path}/{slug}")
```

Align will:
- Auto-detect type (from CLAUDE.md content or ask)
- Run its full DISCOVER → ASSESS → PLAN → IMPLEMENT → VERIFY → DOCUMENT flow
- Create type-aware directories (src/, tests/, docs/architecture/decisions/, venture dirs, etc.)
- Set up SDD, TDD, rules, settings
- Generate the alignment report

**After align completes**, report:

```
New client '{display_name}' ready:
  Path:      {base_path}/{slug}/
  Git:       initialized {+ pushed to github.com/{org}/{slug} if applicable}
  Portfolio: updated
  Alignment: {score from align}/28

  cd {base_path}/{slug}
  /brana:backlog plan — to plan your first phase
```

---

# /brana:onboard (scan) — Existing Behavior

Everything below is the original scan-only flow, unchanged.

## Step Registry (scan)

On entry, create a CC Task step registry. Follow the [guided-execution protocol](../_shared/guided-execution.md).

Register these steps: DETECT, SCAN, RECALL, GAPS, REPORT.

---

## Step 1: Detect project type

```bash
# Code signals
for f in package.json pyproject.toml Cargo.toml go.mod composer.json Gemfile; do
    [ -f "$f" ] && echo "Code: $f"
done

# Venture signals
for d in docs/sops docs/okrs docs/metrics docs/pipeline docs/venture; do
    [ -d "$d" ] && echo "Venture: $d"
done

# Check CLAUDE.md for business keywords
[ -f ".claude/CLAUDE.md" ] && grep -qiE '(venture|business|startup|revenue|pipeline|okr)' ".claude/CLAUDE.md" && echo "Venture: CLAUDE.md keywords"
```

Classify as: **code** (has manifests, no venture dirs), **venture** (has venture dirs, no code), or **hybrid** (both).

## Step 2: Scan structure

### For all clients
- Read `.claude/CLAUDE.md` if it exists
- Check for `docs/architecture/decisions/` (or legacy `docs/decisions/`), `.claude/tasks.json`
- Check auto memory health: `~/.claude/projects/*/memory/MEMORY.md`
  - Over 200 lines? (warn: truncated at session start)
  - Contains directives ("always", "never", "must")? (belongs in rules/)
- Check PM integration: GitHub Issues, project management references

### For code projects (additionally)
- Detect tech stack from manifests
- Check SDD setup: `docs/architecture/decisions/` exists (or legacy `docs/decisions/`) → "SDD enforcement: active"
- Check TDD setup: test framework configured, `tdd-guard` available
- Scan project structure: entry points, key directories, config files

### For venture clients (additionally)

**Voice-first intake check (do this before the discovery interview):**
If `inbox/` contains audio files (`*.ogg`, `*.mp3`, `*.m4a`, `*.wav`) and no `.claude/CLAUDE.md` exists, offer to transcribe before running the discovery interview:
```bash
for f in inbox/*.ogg inbox/*.mp3 inbox/*.m4a inbox/*.wav; do
  [ -f "$f" ] && LD_LIBRARY_PATH=/home/martineserios/.local/lib brana transcribe "$f"
done
```
Consolidate transcripts → write to `inbox/transcripts-YYYY-MM-DD.md` → use as source for CLAUDE.md, ADR-001, and metrics scaffold. Every claim in derived docs must trace to a specific audio.

- Run discovery interview (skip what's obvious from docs or transcripts):
  1. What's the business? One-sentence description.
  2. What stage? Discovery / Validation / Growth / Scale. Revenue? Team size?
  3. Current tools and processes?
  4. Pain points?

> **Discovery output routing — what goes WHERE:**
> - Business identity, domain, pain points, roadmap → CLAUDE.md (via `brana:claudemd generate`)
> - Operational rosters (staff/instructor lists, pricing tables) → `docs/` or external sheet — NOT CLAUDE.md
> - Open questions → `docs/preguntas-{client}.md` (or `docs/open-questions.md`) — NOT CLAUDE.md
> - Status snapshots ("as of [date]") → MEMORY.md — NOT CLAUDE.md
> Never write discovery findings directly into CLAUDE.md. Route through `brana:claudemd generate` which enforces the include/exclude rules.

- Classify stage using the four-stage model:
  - **Discovery:** No revenue, 1-3 people, exploring problem space
  - **Validation:** Some revenue, <$1M ARR, running experiments
  - **Growth:** Repeatable revenue, $1-10M ARR, processes breaking
  - **Scale:** $10M+ ARR, 50+ people, multiple lines
- Check data completeness: audit tables/sheets for empty fields, missing columns
- Assess existing management structure vs stage-appropriate expectations

## Step 3: Recall patterns

```bash
source "$HOME/.claude/scripts/cf-env.sh"
```

Search for patterns relevant to the detected tech stack, domain, or stage:
```bash
[ -n "$CF" ] && cd "$HOME" && $CF memory search --query "{tech stack OR stage keywords}" --limit 10 2>/dev/null || true
```

Fallback: grep `~/.claude/projects/*/memory/MEMORY.md` and `~/.claude/memory/portfolio.md`.

## Step 4: Gap report

**For code projects** — assess against alignment checklist:
- Foundation (git, CLAUDE.md, rules, commits, attribution)
- SDD (architecture/decisions/, ADR, PreToolUse hook)
- TDD (test framework, runner, coverage)

For attribution: check `cat .claude/settings.local.json 2>/dev/null | uv run python3 -c "import json,sys; s=json.load(sys.stdin); print('ok' if s.get('attribution',{}).get('commit','x')=='' and s.get('attribution',{}).get('pr','x')=='' else 'missing')"`. Flag as **missing** if absent or not empty strings.

**Feed coverage check (ADR-055) — for code projects only:** diff the detected stack against the intelligence feed registry:
```bash
brana feed list 2>/dev/null || true
```
A technology counts as covered when a registered feed name starts with its slug (fuzzy prefix: `supabase` matches `supabase-changelog`). For each major uncovered technology that has a public changelog/releases feed (GitHub `releases.atom` is the usual form), include it in the gap report and offer registration in ONE multiSelect AskUserQuestion (never one question per tech):
```bash
brana feed add <feed-url> --name <tech-slug>-changelog
```
Advisory only — skip silently if `brana` is unavailable or the stack list is empty. Full procedure: [brana-feed-inbox guide](../../../docs/guide/features/brana-feed-inbox.md).

**For venture clients** — assess against stage-appropriate items:
- Foundation (description, decision log, metrics, cadence)
- Validation items (hypothesis, MVP, experiments, burn rate)
- Growth items (OKRs, SOPs, meeting cadence, hiring plan)

Classify each as: **present**, **partial**, **missing**.

## Step 5: Output summary

```markdown
## Onboard: {Project Name}

**Type:** {Code | Venture | Hybrid}
**Tech stack:** {if code}
**Stage:** {if venture}
**SDD/TDD:** {active / not configured}

### Structure
{what was found}

### Gaps (prioritized)
**Critical:** ...
**Important:** ...
**Nice-to-have:** ...

### Relevant Patterns
{from Step 3, or "No patterns found"}

### Auto Memory Health
{clean / needs attention}

### Suggested Next Steps
1. Run `/brana:align` to implement recommended structure
2. {most impactful gap to close}
3. {second priority}
```

If no `.claude/CLAUDE.md` exists and this is a new project, offer to create one — delegate to the claudemd skill, do NOT write it inline:
```
Skill("brana:claudemd", args="generate")
```
The claudemd generate flow will interview the user and apply the correct include/exclude constraints. Never write CLAUDE.md content directly from onboard output.

## Rules

- **This is diagnostic — don't create files.** Use `/brana:align` for active structure creation.
- **Auto-detect type, confirm with user.** "This looks like a [code/venture/hybrid] project. Correct?"
- **Stage drives venture recommendations.** Don't recommend Growth frameworks for Discovery-stage businesses.
- **Ask for clarification when needed.** Unusual structure, ambiguous domain, unclear stage — ask.
- **Step registry.** Follow the [guided-execution protocol](../_shared/guided-execution.md). Register steps on entry, update as each completes.

---

## Resume After Compression

If context was compressed and you've lost track of progress:

1. Call `TaskList` — find CC Tasks matching `/brana:onboard — {STEP}` (scan) or `/brana:onboard new — {STEP}` (new client)
2. The `in_progress` task is your current step — resume from there
3. For `new` flow: if CREATE completed but ALIGN didn't start, `cd` into the new directory and invoke `/brana:align`

## Field Notes

### 2026-04-09: Voice-first intake — inbox audio as the only source of context
When a venture dir has audio files in `inbox/` and no CLAUDE.md, transcribing the audio is a fully valid (and sometimes the only) intake path. In the legai session, 5 WhatsApp `.ogg` files yielded the full CLAUDE.md, ADR-001, service table, pricing signals, and competitive context. Flow: `for f in inbox/*.ogg; do LD_LIBRARY_PATH=/home/martineserios/.local/lib brana transcribe "$f"; done` → consolidate → derive docs. Every claim must trace to a specific audio. Errata #114 filed to add this as a documented branch in the onboard procedure (t-3).
Source: /brana:onboard legai session 2026-04-09
