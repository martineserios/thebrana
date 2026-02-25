---
name: reconcile
description: "Detect drift between spec docs and system/ implementation, plan fixes, apply after approval. Use after /maintain-specs changes or periodically to sync specs with implementation."
group: brana
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Task
---

# Reconcile

Compare spec docs (what should be built) against `system/` (what is built). Identify drift, present a remediation plan, apply after approval. Log findings to doc 24.

This is the missing arrow: **specs → existing implementation**. The other commands cover:
- `/build-phase` — specs → new implementation (greenfield)
- `/back-propagate` — implementation → specs (reverse sync)
- `/maintain-specs` — specs → specs (cascade within docs)

`/reconcile` closes the loop: specs evolve, and the built system catches up.

## When to use

- After `/maintain-specs` cascades changes that affect implementation
- After manually editing specs that describe thebrana behavior
- Periodically, to check for accumulated drift
- Before a new `/build-phase`, to ensure the current system matches current specs

## Architecture

After the enter→thebrana merge (ADR-006), specs and implementation coexist in one repo:

```
thebrana/
├── docs/                      ← roadmap specs (00, 15, 17-19, 24, 25, 30, 39)
│   └── reflections/           ← reflection specs (08, 14, 29, 31, 32)
├── system/                    ← implementation (skills, hooks, rules, agents, config)
├── .claude/CLAUDE.md          ← identity + conventions
└── deploy.sh                  ← deployment

brana-knowledge/dimensions/    ← dimension docs (knowledge, cross-repo)
```

Most reconcile work is **intra-repo** (docs/ → system/). Dimension docs in brana-knowledge provide additional spec surface but rarely contain implementation-specific claims.

## Process

### Step 0: Orient

#### 0a: Locate paths

```bash
THEBRANA="$HOME/enter_thebrana/thebrana"
DOCS="$THEBRANA/docs"
REFLECTIONS="$THEBRANA/docs/reflections"
KNOWLEDGE="$HOME/enter_thebrana/brana-knowledge/dimensions"
```

Verify `$THEBRANA` exists. If `$KNOWLEDGE` doesn't exist, note it — dimension docs won't be scanned (acceptable; roadmap and reflection docs contain most implementation-specific claims).

#### 0b: Check working state

Run `git status` in thebrana. If there are uncommitted changes, warn the user:

> "thebrana has uncommitted changes. Reconcile will modify system/ files. Commit or stash first?"

Wait for confirmation before proceeding.

#### 0c: Create branch

Before any edits, create a worktree branch:

```bash
BRANCH="chore/reconcile-$(date +%Y%m%d)"
cd $THEBRANA && git worktree add "$THEBRANA/../thebrana-$BRANCH" -b "$BRANCH"
```

If a branch with that name already exists (second reconcile in one day), append a counter: `-2`, `-3`, etc.

### Step 1: Scan specs (the "should" state)

Read the spec surface — everything that describes what the implementation should look like. Spawn parallel scout agents to scan each area efficiently:

| Spec area | Location | What to extract |
|-----------|----------|----------------|
| **Dimension docs** | `brana-knowledge/dimensions/` (01-07, 09-13, 16, 20-23, 26-28, 33-38) | Tool capabilities, integration patterns, behavioral expectations |
| **Reflection docs** | `docs/reflections/` (08, 14, 29, 31, 32) | Architecture decisions, cross-cutting conventions, quality criteria |
| **Roadmap docs** | `docs/` (15, 17-19, 24, 25, 30) | Implementation details, WI specs, known errata, self-doc expectations |
| **CLAUDE.md** | `.claude/CLAUDE.md` | Commands table, ecosystem roles, rules, memory conventions |
| **Project commands** | `.claude/commands/*.md` | Project-level command definitions |

For each area, extract **concrete claims about the implementation** — things like:
- "skill X should exist with description Y"
- "hook Z should call claude-flow memory store"
- "rule W should enforce convention V"
- "CLAUDE.md should list agent table with these entries"
- "deploy.sh should handle sql.js dependency"

Ignore abstract analysis or research — only extract claims that can be verified against system/ files.

### Step 2: Scan implementation (the "is" state)

Scan `system/` and related implementation files, area by area:

| Area | Files to scan |
|------|--------------|
| **Skills** | `system/skills/*/SKILL.md` — name, description, allowed-tools, body content |
| **Hooks** | `system/hooks/*.sh` — what each hook does, what it calls |
| **Rules** | `system/rules/*.md` — rule names, content, directives |
| **Agents** | `system/agents/*.md` — agent names, models, descriptions |
| **Config** | `system/settings.json` — hook wiring, feature flags |
| **CLAUDE.md** | `system/CLAUDE.md` — identity, agents table, principles, portfolio |
| **Deploy** | `deploy.sh` — deployment steps, dependency handling |

For each file, extract the same kind of concrete claims: "skill build-phase exists with description '...'" , "hook session-start.sh calls memory search", etc.

### Step 3: Diff — identify drift

Compare the "should" claims (Step 1) against the "is" claims (Step 2). Classify each discrepancy:

| Drift type | Description | Example |
|-----------|-------------|---------|
| **Missing** | Spec describes something that doesn't exist | "Spec says agent 'foo' should exist, but agents/ has no foo.md" |
| **Stale** | Implementation contradicts current specs | "Skill description says 'v2 API' but specs now say 'v3 API'" |
| **Incomplete** | Implementation exists but is missing parts the spec requires | "Hook exists but doesn't handle the fallback case spec requires" |
| **Extra** | Implementation has something specs don't mention | Not necessarily wrong — flag for review, don't auto-remove |

**Materiality filter.** Apply the same test proven in `/maintain-specs`: "Would this drift lead to wrong behavior or a wrong implementation decision?" Discard cosmetic differences, minor wording variations, and enhancement suggestions. Only surface drift that matters.

### Step 4: Present drift report

Show the user a structured plan:

```markdown
## Drift Report

**Scanned:** [date]
**Spec surface:** [N] docs (roadmaps + reflections + dimensions)
**Implementation:** [N] files in system/

### Drift by Area

#### Skills ([N] findings)
| # | Type | Finding | Proposed Fix |
|---|------|---------|-------------|
| 1 | Stale | skill X description says "..." but spec now says "..." | Update SKILL.md frontmatter |
| 2 | Missing | spec describes skill Y but it doesn't exist | Create skill Y (note: requires /build-phase) |

#### Hooks ([N] findings)
| # | Type | Finding | Proposed Fix |
|---|------|---------|-------------|

#### Rules ([N] findings)
...

#### Agents ([N] findings)
...

#### Config ([N] findings)
...

#### CLAUDE.md ([N] findings)
...

#### Deploy ([N] findings)
...

### Summary
- **Total drift:** N findings across M areas
- **Auto-fixable:** N (text updates, config changes, metadata corrections)
- **Manual required:** N (new skills to build, architectural changes)

Apply all auto-fixable changes? [y/n]
```

**Wait for user approval.** The report is a proposal, not a commitment.

### Step 5: Apply changes

After approval, apply all auto-fixable changes in the worktree:

1. **Text updates** — Edit SKILL.md frontmatter, rule content, CLAUDE.md sections, hook comments.
2. **Config changes** — Update settings.json entries.
3. **Metadata corrections** — Fix agent descriptions, skill allowed-tools lists.

For each change:
- Use the Edit tool (not Write) to make targeted modifications
- Commit each logical group as a separate commit with conventional commit messages:
  ```
  chore(reconcile): update skill X description to match spec
  chore(reconcile): add missing fallback to session-start hook
  ```

**Do NOT auto-create new skills or make architectural changes.** For "Missing" drift that requires building something new, log it as a backlog item in doc 30 or flag it for `/build-phase`. The reconcile command fixes drift in existing files — it doesn't build new capabilities.

### Step 6: Log to doc 24

Append a reconcile entry to `docs/24-roadmap-corrections.md`:

```markdown
### Reconcile Run — [YYYY-MM-DD]

**Trigger:** [manual | post-maintain-specs | periodic]
**Drift found:** N findings across M areas
**Applied:** N auto-fixes
**Deferred:** N (requires manual build or /build-phase)

| # | Area | Type | Finding | Resolution |
|---|------|------|---------|-----------|
| 1 | Skills | Stale | skill X description outdated | Applied — updated SKILL.md |
| 2 | Hooks | Missing | fallback case not handled | Deferred — logged to doc 30 backlog |
```

Commit the doc 24 update alongside the other changes.

### Step 7: Store in memory

Store the reconcile run in claude-flow for future reference:

```bash
source "$HOME/.claude/scripts/cf-env.sh"

cd "$HOME" && $CF memory store \
  -k "reconcile:brana:$(date +%Y%m%d)" \
  -v "{\"type\": \"reconcile\", \"date\": \"$(date +%Y-%m-%d)\", \"drift_found\": N, \"applied\": N, \"deferred\": N, \"areas\": [\"skills\", \"hooks\", ...]}" \
  --namespace patterns \
  --tags "project:brana,type:reconcile" \
  --upsert
```

If claude-flow is unavailable, append to `~/.claude/projects/*/memory/MEMORY.md`.

### Step 8: Report

```markdown
## Reconcile Complete

**Date:** YYYY-MM-DD
**Branch:** chore/reconcile-YYYYMMDD

### Applied
- [N] auto-fixes across [M] areas
- [list each fix, one line]

### Deferred
- [N] items requiring manual build
- [list each, with suggested next action]

### Commits
- `abc1234` chore(reconcile): [description]
- `def5678` chore(reconcile): [description]

### Merge & Deploy
To merge:
```
cd ~/enter_thebrana/thebrana
git merge --no-ff chore/reconcile-YYYYMMDD
git worktree remove ../thebrana-chore/reconcile-YYYYMMDD
git branch -d chore/reconcile-YYYYMMDD
```

To deploy:
```
cd ~/enter_thebrana/thebrana && ./deploy.sh
```

### Follow-up
- If deferred items exist: consider `/build-phase` or add to doc 30 backlog
```

**Do not auto-merge or auto-deploy.** Present the commands and let the user decide.

## Rules

- **Read before writing.** Always read a file before editing it. Never assume file contents from spec descriptions alone.
- **Materiality filter is strict.** Only surface drift that would cause wrong behavior or wrong implementation decisions. Cosmetic differences are not drift.
- **Never auto-create new capabilities.** Reconcile fixes existing files. New skills, hooks, or agents require `/build-phase` or explicit user instruction.
- **Never auto-delete.** "Extra" items that specs don't mention get flagged for review, not removed. The user decides.
- **One branch, atomic commits.** All reconcile work happens on a single worktree branch with one commit per logical fix.
- **Plan then apply.** Always show the full drift report and get approval before making any changes.
- **Ask for clarification whenever you need it.** If a spec claim is ambiguous, a drift finding is borderline, or the right fix is unclear — ask. Don't guess.
