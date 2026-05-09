# Developer Quickstart

> Add your first skill, rule, or hook to brana in under 10 minutes.

## Prerequisites

- Claude Code installed and running
- This repo cloned locally
- `jq` installed (hooks use it)

```bash
git clone https://github.com/martineserios/thebrana.git
cd thebrana
```

## The Deploy Model

Brana has two layers. Know which one you're touching before you start:

| Layer | What it is | How it loads | How you update it |
|-------|-----------|-------------|-------------------|
| **Plugin** (`system/`) | Skills, hooks, agents, commands | `claude --plugin-dir ./system` | Edit `system/`, restart CC |
| **Identity** (`~/.claude/`) | CLAUDE.md, rules, scripts | Persistent (CC reads at startup) | `./bootstrap.sh` |

**dev mode command:**
```bash
claude --plugin-dir ./system
```

This loads the plugin from your local `system/` directory instead of an installed version. Changes to skill files and hook scripts take effect on the next CC restart. Never edit `~/.claude/` directly.

## Your First Skill (5 minutes)

Skills are slash commands (`/brana:*`) defined as markdown files with YAML frontmatter. Claude follows the body as instructions when the skill is invoked.

### Step 1: Create the skill directory and file

```bash
mkdir -p system/skills/my-skill
```

Create `system/skills/my-skill/SKILL.md`:

```yaml
---
name: my-skill
description: "Check if the current project has a CLAUDE.md. Use when starting work on an unfamiliar project."
group: learning
allowed-tools:
  - Read
  - Glob
  - Bash
  - AskUserQuestion
---

# My Skill

Check whether the current project is brana-aware.

## Step 1: Look for .claude/CLAUDE.md

```bash
ls .claude/CLAUDE.md 2>/dev/null && echo "found" || echo "missing"
```

## Step 2: Report

If found: "This project has a CLAUDE.md at `.claude/CLAUDE.md`. Read it to understand conventions."
If missing: "No `.claude/CLAUDE.md` found. Ask the user if they want to create one."
```

Three things to get right:

**`name`** must match the directory name exactly — `validate.sh` enforces this.

**`description`** is loaded every session and appears in skill discovery. Keep it under 120 characters. Include "Use when" so delegation routing can match it.

**`allowed-tools`** gates what Claude can do during skill execution. Omitting a tool means Claude cannot use it — no exceptions. Start with the minimum and add as needed.

### Step 2: Validate

```bash
./validate.sh
```

Fix any errors before continuing. Common issues:
- `name` field doesn't match directory name
- Missing `allowed-tools`
- Description over context budget

### Step 3: Test in dev mode

```bash
claude --plugin-dir ./system
```

Inside the session:
```
/brana:my-skill
```

Your skill should run. If it doesn't appear, check that `SKILL.md` has valid YAML frontmatter (no tabs, quoted strings).

### Step 4: Commit

```bash
git checkout -b feat/my-skill
git add system/skills/my-skill/
git commit -m "feat(my-skill): check project brana awareness"
```

> Skills live in `system/skills/` which is a BEHAVIORAL_PATH. Commits on `main` are blocked — always branch first.

---

## Your First Rule (3 minutes)

Rules are always-loaded directives. Every token counts — Claude reads them at the start of every session across every project.

Create `system/rules/my-rule.md`:

```markdown
---
description: "Remind Claude to check for CLAUDE.md before starting work."
alwaysApply: true
---

# Project Orientation

Before starting any task in an unfamiliar project, check for `.claude/CLAUDE.md`. If it exists, read it. If it doesn't, ask the user whether to create one before proceeding.
```

Rules deploy via `bootstrap.sh` (identity layer), not the plugin:

```bash
./bootstrap.sh
```

Rules are scoped globally — they apply to every session in every project. Keep them short (under 200 tokens each). If a rule only applies to specific file patterns, add `globs: ["*.py"]` to the frontmatter, but behavioral/process rules work better as unconditional directives.

> Rules path: `system/rules/` is also BEHAVIORAL_PATHS — branch before committing.

---

## Your First Hook (10 minutes)

Hooks run shell scripts in response to CC events (PreToolUse, PostToolUse, SessionStart, SessionEnd). They receive a JSON payload on stdin and must respond with JSON on stdout.

### Where hooks load from

Due to a CC bug (issue #24529), **PostToolUse and PostToolUseFailure hooks only work when deployed to `~/.claude/settings.json`** via `bootstrap.sh`. PreToolUse, SessionStart, and SessionEnd work from the plugin's `hooks.json`.

In practice:
- PreToolUse (gates, spec-first enforcement) → declare in `system/hooks/hooks.json`
- PostToolUse (logging, reactions) → wired by `bootstrap.sh` to `~/.claude/settings.json`

### Create the hook script

Create `system/hooks/my-hook.sh`:

```bash
#!/usr/bin/env bash
# No set -e — hooks must never fail fatally and block the session.

cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true

# Fast exit for irrelevant tools
if [ "${TOOL_NAME:-}" != "Write" ]; then
    echo '{"continue": true}'
    exit 0
fi

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || true

# Only act on Python files
if [[ "$FILE" != *.py ]]; then
    echo '{"continue": true}'
    exit 0
fi

echo '{"continue": true, "additionalContext": "Python file written — remember to run tests."}'
```

Make it executable:

```bash
chmod +x system/hooks/my-hook.sh
```

### Safety rules (non-negotiable)

1. **Never `set -e`** — a hook that exits non-zero blocks the session
2. **Always `|| true`** after commands that might fail
3. **`cd /tmp` first** — the CWD may be a deleted worktree
4. **Fast-exit early** — check `tool_name` immediately, return `{"continue": true}` for irrelevant calls
5. **Stay under the timeout** — default is 5,000ms; expensive ops need a time budget

### Register in hooks.json

For PreToolUse hooks, add to `system/hooks/hooks.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/my-hook.sh",
            "timeout": 3000
          }
        ]
      }
    ]
  }
}
```

For PostToolUse hooks, `bootstrap.sh` wires them. Check `system/scripts/bootstrap-hooks.sh` for how it populates `~/.claude/settings.json`, and add your hook there.

### Deploy and test

```bash
./bootstrap.sh      # deploy identity layer + hook wiring
claude --plugin-dir ./system
```

Trigger the hook by writing a `.py` file in the session. Check output in `/tmp/brana-session-*.jsonl` if you add logging.

---

## The Full Deploy Cycle

```
Edit system/ → ./validate.sh → commit on branch → merge to main
              ↘ ./bootstrap.sh (if rules/hooks changed)
```

| What changed | Command | When it takes effect |
|-------------|---------|---------------------|
| Skill | `claude --plugin-dir ./system` | Next session start |
| Rule | `./bootstrap.sh` | Next session start |
| Hook (PreToolUse) | `claude --plugin-dir ./system` | Next session start |
| Hook (PostToolUse) | `./bootstrap.sh` | Next session start |
| Identity (CLAUDE.md) | `./bootstrap.sh` | Next session start |

`validate.sh` runs these checks before any commit:
- Skill frontmatter completeness (name, description, allowed-tools)
- `name` matches directory name
- `depends_on` references exist
- Context budget compliance (rules not over token limit)
- No secrets in committed files
- Hook scripts are executable

---

## Bundled Scripts

Skills and hooks can ship with helper scripts:

```
system/skills/my-skill/
├── SKILL.md
└── analyze.sh          ← bundled helper
```

Reference from `SKILL.md`:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/my-skill/analyze.sh"
```

Use bundled scripts when the logic is complex enough that inline bash in skill instructions would be fragile. Single-purpose skills with simple logic don't need them.

---

## Next Steps

| Topic | Doc |
|-------|-----|
| Full skill authoring guide | [`extending-skills.md`](extending-skills.md) |
| Hook patterns and safety | [`extending-hooks.md`](extending-hooks.md) |
| Writing agents | [`extending-agents.md`](extending-agents.md) |
| Plugin structure and manifest | [`plugin-structure.md`](plugin-structure.md) |
| Validation and testing | [`testing-validation.md`](testing-validation.md) |
| System architecture | [`overview.md`](overview.md) |
| All skills reference | [`../reference/skills.md`](../reference/skills.md) |
| All hooks reference | [`../reference/hooks.md`](../reference/hooks.md) |
