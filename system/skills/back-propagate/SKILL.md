---
name: back-propagate
description: Propagate implementation changes back to spec docs — update enter/ when thebrana rules, hooks, skills, agents, or config change. Use after building features or changing system files.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Task
---

# Back-Propagate

Sync enter specs (what should be built) with thebrana (what was built). When implementation evolves — new skills, changed hooks, updated rules — the spec docs must catch up.

This is the missing arrow: **implementation → specs**. The other commands cover:
- `/reconcile` — specs → existing implementation (forward sync)
- `/build-phase` — specs → new implementation (greenfield)
- `/maintain-specs` — specs → specs (cascade within docs)

`/back-propagate` closes the loop: implementation evolves, and the spec docs reflect reality.

## When to use

- After building a new skill, agent, hook, or rule in thebrana
- After modifying system files (CLAUDE.md, settings.json, deploy.sh)
- After `/build-phase` completes — propagate what was actually built back to specs
- When `/debrief` findings include implementation changes
- When delegation-routing triggers: "Changed rule/hook/skill/config"

## Process

### Step 0: Orient

#### 0a: Locate repos

```bash
ENTER="$HOME/enter_thebrana/enter"
THEBRANA="$HOME/enter_thebrana/thebrana"
```

Verify both exist. If either is missing, abort with a clear message.

#### 0b: Check working state

Run `git status` in enter. If enter has uncommitted changes, warn the user:

> "enter has uncommitted changes. Back-propagate will modify spec files. Commit or stash first?"

Wait for confirmation before proceeding.

#### 0c: Create branch

Before any edits, create a worktree branch in enter:

```bash
BRANCH="docs/backprop-$(date +%Y%m%d)"
git -C $ENTER worktree add "$ENTER/../enter-$BRANCH" -b "$BRANCH"
```

If a branch with that name already exists (second backprop in one day), append a counter: `-2`, `-3`, etc.

All spec edits happen in the worktree. Reference the worktree path as `$WORKTREE` in subsequent steps.

### Step 1: Detect changes

Two modes — pick based on user input:

#### Mode A: User description

If `$ARGUMENTS` is provided (e.g., `/back-propagate added /gsheets skill and venture agents`), use that as the change description. Skip git scanning.

Parse the description to build a change manifest:

| Area | Changes |
|------|---------|
| Skills | [extracted from description] |
| Agents | [extracted from description] |
| Hooks | [extracted from description] |
| Rules | [extracted from description] |
| Config | [extracted from description] |
| CLAUDE.md | [extracted from description] |
| Deploy | [extracted from description] |

#### Mode B: Git scan

If no `$ARGUMENTS`, scan thebrana for recent changes:

```bash
cd $THEBRANA
git log --oneline --since="7 days ago" --name-only
```

If empty, widen to 30 days:

```bash
git log --oneline --since="30 days ago" --name-only
```

Group changed files into areas:

| File pattern | Area |
|-------------|------|
| `system/skills/*/SKILL.md` | Skills |
| `system/agents/*.md` | Agents |
| `system/hooks/*.sh` | Hooks |
| `system/rules/*.md` | Rules |
| `system/settings.json` | Config |
| `system/CLAUDE.md` | CLAUDE.md |
| `deploy.sh` | Deploy |

Build the same change manifest as Mode A.

If both modes produce no changes, report "No recent implementation changes found" and stop.

### Step 2: Map to spec docs

For each change area, identify which enter docs need updating. Core mapping:

| Change area | Primary docs | Secondary docs |
|------------|-------------|----------------|
| Skills | 14 (Architecture), 25 (Self-doc) | Domain dimension doc for the skill's topic |
| Agents | 14 (Architecture), 25 (Self-doc) | Domain dimension doc for the agent's topic |
| Hooks | 14 (Architecture), 25 (Self-doc) | — |
| Rules | Relevant dimension doc, 14 (Architecture) | — |
| CLAUDE.md | 14 (Architecture), 00 (Foundation) | — |
| Config | 14 (Architecture), 25 (Self-doc) | — |
| Deploy | 14 (Architecture), 25 (Self-doc) | — |

**Safety net:** Also grep enter/ for direct references to the changed files or concepts:

```bash
cd $ENTER && grep -rl "changed-concept" *.md
```

Add any discovered docs to the mapping.

### Step 3: Present update plan

Read each mapped spec doc. For each, identify the specific section that needs updating and what the update should be.

Present a structured plan:

```markdown
## Back-Propagation Plan

**Source:** [Mode A description / Mode B git scan since DATE]
**Changes detected:** N changes across M areas

### Proposed Updates

| # | Doc | Section | Update type | Description |
|---|-----|---------|-------------|-------------|
| 1 | 14 | §Skills table | Add row | New skill /foo with description "..." |
| 2 | 25 | §Maintenance commands | Add entry | /foo command added |
| 3 | 07 | §Tools | Add paragraph | /foo integrates with topic X |

### No update needed
- Doc 08: reviewed, no relevant sections
- Doc 32: reviewed, not affected
```

**Materiality filter:** Only propose updates where the spec is materially incomplete or wrong. Skip cosmetic tweaks. Ask: "Would someone reading this spec make a wrong implementation decision because this info is missing?"

**Wait for user approval** before applying any changes.

### Step 4: Apply updates

After approval, apply changes layer by layer:

1. **Dimension docs first** (01-07, 09-13, 20-23, 26-28, 33) — these are the source of truth
2. **Reflection docs** (08, 14, 29, 31, 32) — cross-cutting synthesis
3. **Roadmap docs** (15, 17-19, 24, 25, 30) — implementation tracking
4. **Doc 00** (Foundation) — if user practices or preferences changed

For each edit:
- **Read the target file first.** Never edit without reading.
- Use the **Edit tool** for targeted modifications. Match the existing doc's voice, formatting, and level of detail.
- Insert new content near related existing content — don't append randomly.

Commit each logical group in the worktree:

```bash
cd $WORKTREE
git add [changed-files]
git commit -m "docs(NN,MM): back-propagate [description]"
```

Use the same commit format as past manual backprops: `docs(NN,MM): back-propagate [description]` where NN,MM are the doc numbers changed.

### Step 5: Log to doc 24

If drift was found (specs were wrong or materially incomplete), append a brief entry to `24-roadmap-corrections.md`:

```markdown
### Back-Propagation — [YYYY-MM-DD]

**Trigger:** [/back-propagate description | git scan]
**Docs updated:** [list]
**Finding:** [brief description of what specs were missing]
```

If the backprop was purely additive (specs weren't wrong, just didn't cover new features yet), skip this step — doc 24 is for corrections and errata, not routine additions.

### Step 6: Store in memory

Store the backprop run in claude-flow:

```bash
source "$HOME/.claude/scripts/cf-env.sh"

cd "$HOME" && $CF memory store \
  -k "backprop:brana:$(date +%Y%m%d)" \
  -v "{\"type\": \"backprop\", \"date\": \"$(date +%Y-%m-%d)\", \"docs_updated\": [NN, MM], \"areas\": [\"skills\", \"agents\"], \"description\": \"brief summary\"}" \
  --namespace patterns \
  --tags "project:brana,type:backprop" \
  --upsert
```

If claude-flow is unavailable, append to `~/.claude/projects/*/memory/MEMORY.md`.

### Step 7: Report

```markdown
## Back-Propagation Complete

**Date:** YYYY-MM-DD
**Branch:** docs/backprop-YYYYMMDD (in enter worktree)

### Updates Applied
- [list each doc updated with one-line description]

### Commits
- `abc1234` docs(NN,MM): back-propagate [description]

### Merge
To merge into enter/main:
```
cd ~/enter_thebrana/enter
git merge --no-ff docs/backprop-YYYYMMDD
git worktree remove ../enter-docs/backprop-YYYYMMDD
git branch -d docs/backprop-YYYYMMDD
```

### Follow-up
- If updates touched multiple layers: consider `/maintain-specs` for deeper cascade
- If findings were significant: consider `/debrief` to capture learnings
```

**Do not auto-merge.** Present the commands and let the user decide.

## Rules

- **Read before writing.** Always read a file before editing it. Never assume file contents from spec descriptions alone.
- **Materiality filter is strict.** Only update specs where the missing information would lead to wrong implementation decisions. Don't add cosmetic detail.
- **Never auto-delete spec content.** If implementation removed something that specs describe, flag it for review — don't silently remove spec text.
- **Dimension docs first.** They are the source of truth. Reflection and roadmap docs derive from dimensions.
- **Worktrees for branches.** Follow git-discipline.md — create worktree, work there, merge from main worktree.
- **Plan then apply.** Always show the full update plan and get approval before making any changes.
- **Match existing voice.** Each spec doc has its own style and depth level. New content should blend in, not stand out.
- **One commit per logical group.** If updating docs 14 and 25 for the same change, that's one commit. Different changes get different commits.
- **No scout agents needed.** Back-propagation typically reads 3-5 files in thebrana and edits 2-4 files in enter. The context cost is low — no need to delegate to agents.
