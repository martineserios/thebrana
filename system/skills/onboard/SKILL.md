---
name: onboard
description: "Scan and diagnose a project — tech stack, structure, stage, gaps, patterns. Works for code and venture clients. Auto-detects project type. Use when entering an unfamiliar project for the first time."
effort: medium
keywords: [scan, diagnose, project, structure, tech-stack, gaps]
task_strategies: [investigation, greenfield]
stream_affinity: [roadmap]
argument-hint: "[project-path]"
group: execution
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - Write
  - AskUserQuestion
  - Task
---

# Onboard — Project Discovery

Diagnostic entry point for any project. Scans what exists, detects type (code, venture, or hybrid), recalls relevant patterns, assesses health, and outputs a structured report.

Replaces `/project-onboard` and `/venture-onboard`.

## When to use

First session on a new project, when taking over an existing project, or as a periodic health check.

## Step Registry

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

1. Call `TaskList` — find CC Tasks matching `/brana:onboard — {STEP}`
2. The `in_progress` task is your current step — resume from there
