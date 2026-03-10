# Extending Agents

> How to add a specialized agent to the brana system. Agents are sub-processes spawned via Claude Code's Agent tool. They work autonomously, return findings, and never modify files.

## Agent Definition Anatomy

Every agent lives at `system/agents/{name}.md`. The file has YAML frontmatter and a markdown body with instructions.

```yaml
---
name: my-agent
description: "One-line with 'Use when' and 'Not for' guidance. Use when starting work on unfamiliar codebases. Not for: venture projects, session debrief."
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
Read files, search code, run diagnostic commands.

## Step 2: Analyze
Identify patterns, gaps, and recommendations.

## Output Format
Return a structured summary:
- Key findings (with file paths and evidence)
- Recommendations (prioritized)
- Confidence levels (high/medium/low)
```

### Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Agent name. Must match filename (without `.md`). |
| `description` | Yes | One-line description with "Use when" and "Not for" guidance. Loaded every session — counts toward context budget. |
| `model` | Yes | Which model runs the agent: `haiku`, `sonnet`, or `opus`. |
| `tools` | Yes | List of tools the agent may use. |
| `disallowedTools` | Yes | List of tools the agent must not use. Always includes `Write`, `Edit`, `NotebookEdit`. |

### Description Format

The description serves double duty: it tells users what the agent does and it tells Claude's delegation logic when to spawn it. Include both positive ("Use when") and negative ("Not for") guidance:

```yaml
description: "Scan project structure and detect tech stack. Use when entering an unfamiliar project or checking project health. Not for: venture analysis, code review, session debrief."
```

Keep descriptions under 200 characters. They are loaded into context every session.

## When to Use Agents vs Skills

| Use an agent when... | Use a skill when... |
|---------------------|---------------------|
| The task is investigative (gather, analyze, report) | The task involves action (write, edit, build) |
| Findings need user approval before acting | The user already approved the action |
| Auto-delegation makes sense (fires without being asked) | Explicit invocation is appropriate (`/brana:name`) |
| Context isolation matters (separate reasoning context) | Shared context is needed (access to conversation history) |

Agents and skills often work together. A skill may spawn an agent for a research phase, then act on findings in the main context. For example, `/brana:build` spawns the `challenger` agent during SPECIFY, then incorporates findings into the feature spec.

## Tool Sandboxing

All brana agents share a core restriction: they cannot modify files. The `disallowedTools` list always includes:

```yaml
disallowedTools:
  - Write
  - Edit
  - NotebookEdit
```

This is a design principle, not a limitation. Agents return findings; the main context (with user approval) acts on them. This prevents agents from making unauthorized changes.

### Allowed Tool Patterns

| Pattern | Tools | Agents using it |
|---------|-------|----------------|
| Code exploration | `Read, Glob, Grep` | challenger |
| Code + CLI | `Bash, Read, Glob, Grep` | memory-curator, client-scanner, debrief-analyst, pr-reviewer |
| Web research | `Read, Glob, Grep, WebSearch, WebFetch` | scout |

Agents with `Bash` access use it for CLI tools like `gh`, `git`, and `claude-flow` — not for file modification.

### Agent Sandbox Boundaries

Agents run in Claude Code's sandbox. Key constraints:

- **General-purpose agents CAN read files at arbitrary absolute paths** (cross-repo, `/tmp`, etc.)
- **Scout/explore agents are more restricted** — they may not read outside the project directory
- **No agent can write files** — findings go back to main context as text output
- **Agents cannot spawn other agents** — only the main context or skills with `Agent` in allowed-tools can delegate

## Model Routing Guidelines

The `model` field controls cost, speed, and reasoning depth:

| Model | Cost | Speed | When to use |
|-------|------|-------|-------------|
| `haiku` | Low | Fast | Data collection, scanning, pattern matching. Most agents use this. |
| `sonnet` | Medium | Moderate | Code review, moderate analysis requiring nuanced judgment. |
| `opus` | High | Slower | Deep reasoning, adversarial review, complex synthesis. Reserve for high-value decisions. |

Current brana agent model assignments:

- **Haiku:** scout, memory-curator, client-scanner, venture-scanner, daily-ops, metrics-collector, pipeline-tracker, archiver
- **Sonnet:** pr-reviewer
- **Opus:** challenger, debrief-analyst

Default to `haiku` unless the task requires deeper reasoning. Upgrading a model is cheap to try — downgrading after users depend on quality is not.

## Registering in CLAUDE.md

After creating the agent, add it to the agents table in `system/CLAUDE.md`:

```markdown
| Agent | Model | When It Fires |
|-------|-------|---------------|
| my-agent | Haiku | [trigger description] |
```

This table is loaded every session. It tells Claude which agents exist and when to consider spawning them.

## Auto-Delegation

To make an agent fire automatically (without the user asking), add a trigger to the delegation routing. Two places need updating:

### 1. `system/CLAUDE.md` agents table

The table in CLAUDE.md tells Claude the agent exists and its trigger condition.

### 2. Bootstrap rules

If the delegation routing rule in `~/.claude/rules/delegation-routing.md` has a triggers table, add the new agent's trigger there:

```markdown
| Trigger | Action |
|---------|--------|
| [situation description] | delegate to my-agent |
```

Auto-delegation is rule-based, not hook-based. Claude reads the agents table and delegation rules at session start and decides when conditions match during the session.

## Complete Example

A minimal agent that checks for stale branches:

```
system/agents/branch-auditor.md
```

```yaml
---
name: branch-auditor
description: "Audit git branches for staleness and merge status. Use when cleaning up a repo or during periodic maintenance. Not for: active development, code review."
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

# Branch Auditor

You are a branch audit agent. Your job is to identify stale, merged, or orphaned branches.

## Step 1: List branches

```bash
git branch -a --sort=-committerdate --format='%(refname:short) %(committerdate:relative) %(upstream:track)'
```

## Step 2: Classify

For each branch:
- **Merged:** already merged to main (can be deleted)
- **Stale:** no commits in 30+ days
- **Active:** recent commits, not merged
- **Orphaned:** no upstream, no recent activity

## Step 3: Report

| Branch | Status | Last commit | Action |
|--------|--------|------------|--------|
| feat/old-thing | Stale | 45 days ago | Delete? |
| fix/resolved | Merged | 3 days ago | Delete |

Never delete branches yourself. Return the list for the user to decide.
```

## Validation

`validate.sh` checks agents automatically:

- Frontmatter has valid YAML
- `name` and `description` fields are present
- Description counts toward context budget (warn if total exceeds thresholds)

```bash
./validate.sh
```

## Checklist

1. Create `system/agents/{name}.md` with frontmatter and instructions
2. Always include `Write`, `Edit`, `NotebookEdit` in `disallowedTools`
3. Choose the right model (default to `haiku`)
4. Run `./validate.sh`
5. Add to agents table in `system/CLAUDE.md`
6. If auto-delegation is needed, add trigger to delegation routing
7. Add entry to `docs/architecture/agents.md` roster
8. Test by spawning manually: `Agent(subagent_type="my-agent", prompt="...")`
