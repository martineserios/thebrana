# Extending Skills

> How to add a new skill to the brana plugin. Skills are slash commands (`/brana:*`) defined as markdown files with YAML frontmatter.

## Skill Anatomy

Every skill lives at `system/skills/{name}/SKILL.md`. The directory name **is** the skill name.

```yaml
---
name: my-skill
description: "One-line description — what it does and when to use it."
group: execution
depends_on:
  - backlog
allowed-tools:
  - Read
  - Glob
  - Grep
  - AskUserQuestion
---

# My Skill

Instructions for Claude when `/brana:my-skill` is invoked.

## Step 1: Gather context
Read relevant files...

## Step 2: Do the work
...
```

### Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Must match the directory name exactly. `validate.sh` checks this. |
| `description` | Yes | One-line description. Shows in help text and skill discovery. Loaded every session (counts toward context budget). |
| `group` | No | Organizational group: `execution`, `session`, `learning`, `business`, `integration`. Used for catalog grouping, not runtime behavior. |
| `depends_on` | No | List of other skill names this skill references. `validate.sh` checks that all listed skills exist. |
| `context` | No | Set to `fork` to run the skill in a forked context (separate from main conversation). |
| `allowed-tools` | Yes | List of tools Claude may use during skill execution. Unlisted tools are blocked. |

### Allowed Tools

The `allowed-tools` list gates what Claude can do while the skill is active. Common patterns:

| Pattern | Tools | Use case |
|---------|-------|----------|
| Read-only | `Read, Glob, Grep, WebSearch` | Research, analysis, diagnostics |
| Interactive | Add `AskUserQuestion` | Any skill that needs user input (preferred over plain text prompts) |
| Action | Add `Write, Edit, Bash` | Skills that modify files or run commands |
| Delegation | Add `Agent` or `Task` | Skills that spawn sub-agents |
| MCP | Add specific MCP tool names | Skills that use external integrations |

All 26 brana skills include `AskUserQuestion` — use it for confirmations, choices, and multi-option prompts instead of plain text questions.

### Body Format

The markdown body after the frontmatter is the skill's instruction set. Claude follows these instructions when the skill is invoked. Structure them as numbered steps with clear exit conditions.

Good practices:
- Start with a context-gathering step (read files, check state)
- Include explicit user confirmation gates before destructive actions
- End with a report/summary step
- Use code blocks for command examples Claude should run
- Reference other skills with `/brana:{name}` when handoff is appropriate

## Naming Conventions

- **Directory name** = skill name. No prefix needed — the plugin adds `brana:` automatically.
- Use lowercase, hyphenated names: `my-skill`, not `mySkill` or `my_skill`.
- Name the skill after what it **does**, not what it **is**: `build`, not `builder`.

## Group Assignment

Groups organize skills in the catalog (`docs/architecture/skills.md`). Pick the closest fit:

| Group | Skills in this group do... |
|-------|---------------------------|
| `execution` | Build, ship, maintain code |
| `session` | Manage session lifecycle (start, close) |
| `learning` | Learn, recall, align knowledge |
| `business` | Manage business projects and ventures |
| `integration` | Connect to external tools and platforms |

## Bundled Scripts

Skills can include helper scripts alongside `SKILL.md`:

```
system/skills/my-skill/
├── SKILL.md
├── analyze.sh
└── transform.py
```

Reference them in the skill body using `${CLAUDE_PLUGIN_ROOT}`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/my-skill/analyze.sh" "$INPUT"
```

Use bundled scripts when the logic is complex enough that inline bash in the skill instructions would be fragile or hard to maintain.

## Complete Minimal Example

A read-only skill that checks project health:

```
system/skills/health-check/SKILL.md
```

```yaml
---
name: health-check
description: "Check project health — tests, docs, task status. Use when starting work on a project or during periodic review."
group: learning
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - AskUserQuestion
---

# Health Check

Scan the current project and report on its health.

## Step 1: Detect project type

Look for:
- `package.json`, `pyproject.toml`, `Cargo.toml` (code project)
- `docs/sops/`, `docs/okrs/` (venture project)
- `.claude/CLAUDE.md` (brana-aware project)

## Step 2: Run checks

For code projects:
1. Check if tests exist and pass: `npm test` / `pytest` / equivalent
2. Check if `.claude/tasks.json` exists and has no stale `in_progress` tasks
3. Check if `docs/decisions/` exists (spec-first enforcement)

For venture projects:
1. Check for recent entries in `docs/metrics/`
2. Check pipeline status in `docs/pipeline/`

## Step 3: Report

Present findings as a table:

| Check | Status | Detail |
|-------|--------|--------|
| Tests | pass/fail/missing | N tests, M failures |
| Tasks | clean/stale | N in_progress older than 7 days |
| Specs | enabled/disabled | docs/decisions/ present? |
```

## Testing Locally

Use dev mode to test without installing:

```bash
# Start Claude Code with the plugin loaded from local source
claude --plugin-dir ./system

# In the session, invoke your skill
/brana:health-check
```

Changes to `SKILL.md` take effect on the next session (restart Claude Code).

## Validation

Before committing, run `validate.sh` to catch common issues:

```bash
./validate.sh
```

It checks:
- Frontmatter has valid YAML with `name` and `description`
- `name` field matches directory name
- `depends_on` references point to existing skills
- No duplicate skill names across the system
- File is under 50KB
- No secrets in the file

## Checklist

1. Create `system/skills/{name}/SKILL.md` with frontmatter and instructions
2. Run `./validate.sh` — fix any errors
3. Test with `claude --plugin-dir ./system`
4. Add entry to `docs/architecture/skills.md` catalog
5. If the skill auto-triggers, add routing to `delegation-routing` rule
