
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
| base_path | "Location?" | `~/enter_thebrana/clients/` (recommended) / custom path | `~/enter_thebrana/clients/` |
| github | "Create GitHub remote?" | yes / no | no |
| github_org | (only if github=yes) "GitHub org?" | martineserios / other | martineserios |
| github_visibility | (only if github=yes) "Visibility?" | private (recommended) / public | private |

### Flag overrides (skip prompts)

```
/brana:onboard new myproject --type venture --path ~/other/place --github --org myorg
```

Any flag provided skips that prompt.

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

Append to `~/.claude/memory/portfolio.md` under `## Clients`:

```markdown
### {slug}
- **Type:** {type} — {description}
- **Projects:** {slug} (`clients/{slug}`)
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
- Create type-aware directories (src/, tests/, docs/decisions/, venture dirs, etc.)
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
- Check for `docs/decisions/`, `.claude/tasks.json`
- Check auto memory health: `~/.claude/projects/*/memory/MEMORY.md`
  - Over 200 lines? (warn: truncated at session start)
  - Contains directives ("always", "never", "must")? (belongs in rules/)
- Check PM integration: GitHub Issues, project management references

### For code projects (additionally)
- Detect tech stack from manifests
- Check SDD setup: `docs/decisions/` exists → "SDD enforcement: active"
- Check TDD setup: test framework configured, `tdd-guard` available
- Scan project structure: entry points, key directories, config files

### For venture clients (additionally)
- Run discovery interview (skip what's obvious from docs):
  1. What's the business? One-sentence description.
  2. What stage? Discovery / Validation / Growth / Scale. Revenue? Team size?
  3. Current tools and processes?
  4. Pain points?
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
- Foundation (git, CLAUDE.md, rules, commits)
- SDD (decisions/, ADR, PreToolUse hook)
- TDD (test framework, runner, coverage)

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

If no `.claude/CLAUDE.md` exists and this is a new project, offer to create an initial one.

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
