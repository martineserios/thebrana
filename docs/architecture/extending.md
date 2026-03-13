# Extending Brana

> How to add skills, rules, hooks, and agents to the system. All changes go through `system/` — never edit `~/.claude/` directly.

## Adding a Skill

### 1. Create the skill file

```bash
mkdir -p system/skills/my-skill
```

Create `system/skills/my-skill/SKILL.md`:

```yaml
---
name: my-skill
description: "One-line description — what it does and when to use it."
allowed-tools:
  - Read
  - Glob
  - Grep
  - AskUserQuestion
  - Agent
  - Bash
  - Write
  - Edit
---

# My Skill

Instructions for Claude when `/my-skill` is invoked.

## Step 1: Gather context
Read relevant files...

## Step 2: Do the work
...
```

### 2. Key decisions

**allowed-tools** — List every tool the skill may use. Omitting a tool means Claude cannot use it during skill execution. Common patterns:
- Read-only skills: `Read, Glob, Grep, WebSearch`
- Interactive skills: add `AskUserQuestion` (preferred over plain text prompts)
- Action skills: add `Write, Edit, Bash`
- Delegation skills: add `Agent`

**Bundled scripts** — Per ADR-011, skills can bundle helper scripts alongside `SKILL.md`. Place them in the same directory:

```
system/skills/my-skill/
├── SKILL.md
├── analyze.sh
└── transform.py
```

Reference them in the skill instructions. Scripts run via `~/.claude/skills/my-skill/analyze.sh` after deploy.

### 3. Validate and deploy

```bash
./validate.sh && ./deploy.sh
```

`validate.sh` checks frontmatter fields, context budget, and secrets.

## Adding a Rule

### 1. Create the rule file

Create `system/rules/my-rule.md`:

```markdown
# My Rule

## Purpose
One sentence on what this rule enforces.

## Directives
- **Always** do X when Y
- **Never** do Z in context W
- **Prefer** A over B
```

### 2. Scoping

Rules are **always loaded** by default — they apply to every session in every project.

To scope a rule to specific file patterns, add `paths:` to the frontmatter. Note: `paths:` only matches file patterns (e.g., `*.py`, `docs/**`), not project structure. For behavioral/process rules, keep them unconditional and short.

### 3. Keep rules concise

Rules sit in the context window every session. Each line costs tokens. Write opinionated, concrete directives — not explanations. Use 2-3 line examples where the behavior isn't obvious.

### 4. Validate and deploy

```bash
./validate.sh && ./deploy.sh
```

## Adding a Hook

### 1. Create the hook script

Create `system/hooks/my-hook.sh`:

```bash
#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# Description of what this hook does.
# Input:  stdin JSON (session_id, tool_name, tool_input, cwd)
# Output: stdout JSON

cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true

# Fast exit for irrelevant tools
if [ "${TOOL_NAME:-}" != "TargetTool" ]; then
    echo '{"continue": true}'
    exit 0
fi

# ... your logic here ...

echo '{"continue": true, "additionalContext": "Hook found something relevant."}'
```

### 2. Safety conventions

- **Never use `set -e`** — hooks must not fail fatally
- **Always use `|| true`** fallbacks on every command that might fail
- **`cd /tmp`** at the start — the CWD might be a deleted worktree
- **Fast exit** — check the tool name first, return `{"continue": true}` for irrelevant calls
- **Timeout-aware** — keep execution under the configured timeout (typically 5,000ms)

### 3. Register in settings.json

Add to `system/settings.json` under the appropriate event:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/my-hook.sh",
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

**matcher** options:
- `"Write|Edit"` — pipe-separated tool names
- `"Bash"` — single tool
- `""` — all tools (used by SessionStart/SessionEnd)

### 4. Validate and deploy

```bash
./validate.sh && ./deploy.sh
```

## Adding an Agent

### 1. Create the agent file

Create `system/agents/my-agent.md`:

```yaml
---
name: my-agent
description: "One-line with 'Use when' and 'Not for' guidance."
model: haiku
tools:
  - Bash
  - Read
  - Glob
  - Grep
disallowedTools:
  - Write
  - Edit
  - NotebookEdit
---

# My Agent

You are a [role] agent. Your job is to [purpose]. You do NOT modify files — you return structured findings to the main context.

## Step 1: Gather data
...

## Step 2: Analyze
...

## Output format
Return a structured summary with:
- Key findings
- Recommendations
- Confidence levels
```

### 2. Model selection

| Model | Cost | When to use |
|-------|------|-------------|
| Haiku | Low | Fast tasks: scanning, searching, collecting data |
| Sonnet | Medium | Moderate analysis: code review, pattern matching |
| Opus | High | Deep reasoning: adversarial review, complex synthesis |

### 3. Tool restrictions

All brana agents disallow `Write`, `Edit`, and `NotebookEdit`. Agents are read-only by design — they return findings for the user to approve. Some agents have `Bash` for CLI tools (`gh`, `git`, `ruflo`).

### 4. Auto-delegation

To make the agent fire automatically, add a trigger to `system/rules/delegation-routing.md`:

```markdown
| Trigger | Agent |
|---------|-------|
| [When this situation is detected] | my-agent |
```

### 5. Validate and deploy

```bash
./validate.sh && ./deploy.sh
```

## The Deploy Cycle

Every change follows the same pattern:

```
Edit system/ → ./validate.sh → ./deploy.sh → New session picks it up
```

### validate.sh

Pre-deploy checks:
- Skill frontmatter completeness (name, description, allowed-tools)
- Context budget compliance (rules aren't too large)
- No secrets in committed files
- Hook scripts are executable

### deploy.sh

Copies `system/` contents to `~/.claude/`:
1. Skills → `~/.claude/skills/`
2. Rules → `~/.claude/rules/`
3. Hooks → `~/.claude/hooks/`
4. Agents → `~/.claude/agents/`
5. Scripts → `~/.claude/scripts/`
6. Commands → `~/.claude/commands/`
7. Settings → `~/.claude/settings.json`
8. CLAUDE.md → `~/.claude/CLAUDE.md`
9. Embeddings config → `~/.claude-flow/embeddings.json`

### Testing

After deploy:
1. Start a new Claude Code session
2. Verify session-start hooks fire
3. Test your new component:
   - Skill: invoke it with `/{name}`
   - Rule: check it appears in context
   - Hook: trigger the relevant tool and check output
   - Agent: trigger its auto-delegation condition or spawn manually

For hooks, check `/tmp/brana-session-*.jsonl` for logged events.
