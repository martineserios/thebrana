---
name: docs
description: "Generate and update living documentation — tech docs, user guides, philosophy overview. Composable building block for CLOSE and other skills."
effort: medium
argument-hint: "guide|tech|overview|all [task-id]"
group: core
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
---

# Living Documentation

Generate and update project documentation from build context. Works standalone or as a building block invoked by other skills (CLOSE, reconcile, maintain-specs).

## When to use

- After building a feature — generate tech doc + user guide
- After `/brana:build` CLOSE step — invoked automatically via `all`
- Manually — update philosophy, regenerate stale docs, or fill doc gaps
- From other skills — any skill can invoke `/brana:docs` for its doc needs

## Subcommands

```
/brana:docs tech [task-id]       — generate/update tech doc for a feature
/brana:docs guide [task-id]      — generate/update user guide for a feature
/brana:docs overview             — update philosophy.md with latest patterns
/brana:docs all [task-id]        — run tech + guide + shared doc updates + overview
```

---

## /brana:docs tech

Generate or update a technical architecture doc for a feature.

### Input sources

Gather context from (in priority order):
1. **Task metadata** (if task-id provided): `brana backlog get {task-id}` — subject, description, context, strategy, tags
2. **Git diff**: `git diff main...HEAD --stat` — what files changed
3. **Feature spec**: check `docs/architecture/features/` for existing spec matching the task slug
4. **Design decisions**: from task context field and any ADRs created during the build

### Output

Write to `docs/architecture/features/{feature-slug}.md` using the template at `system/skills/build/templates/tech-doc.md`.

### Steps

1. Gather input sources (parallel where possible)
2. If a tech doc already exists for this feature:
   - Read it
   - Show diff preview of proposed changes
   - Ask: "Update existing doc?" via AskUserQuestion
3. If no doc exists:
   - Fill template from gathered context
   - Write the file
4. Report: "Tech doc written: `docs/architecture/features/{slug}.md`"

### Template field mapping

| Template field | Source |
|---------------|--------|
| `{feature-name}` | Task subject |
| `{date}` | Today's date |
| `{task-id}` | Task ID |
| `{branch}` | Current branch or task branch field |
| Goal | Task description + context |
| Design Decisions | Task context (decision entries), ADRs, feature spec |
| Code Flow | Git diff analysis — entry points, core logic, outputs |
| Key Files | Files from `git diff --name-only main...HEAD` |
| API Surface | Public commands, functions, config exposed |
| Testing | Test files in diff, how to run them |
| Known Limitations | From task context (challenger findings, deferred items) |

---

## /brana:docs guide

Generate or update a user-facing guide for a feature.

### Input sources

Same as `tech`, plus:
- **Skill frontmatter** (if the feature is a skill): read SKILL.md for user-facing description, argument-hint
- **Command reference**: check `docs/guide/commands/index.md` for existing entry

### Output

Write to `docs/guide/features/{feature-slug}.md` using the template at `system/skills/build/templates/user-guide.md`.

### Steps

1. Gather input sources
2. If a guide already exists:
   - Read it, show diff preview, ask to update
3. If no guide exists:
   - Fill template — focus on copy-pasteable examples and observable behavior
   - Write the file
4. **Update shared docs** (only for new commands/skills):
   - Check `docs/guide/commands/index.md` — if the feature adds a new command, insert a row in the appropriate workflow group table
   - Check `docs/guide/workflows/` — if the feature changes a workflow, flag which files need updating
5. Report: "User guide written: `docs/guide/features/{slug}.md`"

### Shared doc updates

When a feature adds a new skill or command:

1. Read `docs/guide/commands/index.md`
2. Find the workflow group table that best fits (Build & Development, Task Management, etc.)
3. Insert `| /brana:{name} | {description from skill frontmatter} |`
4. If no group fits, add to "Utilities"

When a feature changes an existing workflow:
1. Identify affected workflow files via spec-graph routing (if available) or keyword match
2. Show the user which files may need updates
3. Let the user decide — don't auto-edit workflow docs (too high risk of breaking coherence)

---

## /brana:docs overview

Update the philosophy document with patterns and principles from recent work.

### Output

Write or update `docs/guide/philosophy.md`.

### Steps

1. Read `docs/guide/philosophy.md` (if it exists)
2. Scan recent build context for system-level patterns:
   - Design principles exercised (composability, TDD, etc.)
   - Architecture decisions that reveal the "why"
   - Cross-cutting patterns (how skills compose, how knowledge flows)
3. If philosophy.md exists: append new insights (don't rewrite existing content)
4. If philosophy.md doesn't exist: generate seed content from project CLAUDE.md + key architecture docs
5. Keep it concise — philosophy.md should be readable in 5 minutes

### Philosophy doc structure

```markdown
# Philosophy

{1-2 sentences: what this system is and why it exists.}

## Core Principles

### {Principle 1}
{2-3 sentences. Concrete, not abstract.}

### {Principle 2}
...

## Design Decisions That Matter

{Key architectural choices and WHY they were made. Not a list of features — a list of tradeoffs.}

## How It All Connects

{The big picture: how skills, hooks, rules, agents, and knowledge work together.}
```

---

## /brana:docs all

Orchestrate all doc generation for a completed feature. This is what CLOSE invokes.

### Steps

1. **Determine strategy** from task metadata:
   ```bash
   brana backlog get {task-id} --field strategy
   ```

2. **Strategy-aware generation:**

   | Strategy | Tech Doc | User Guide | Overview |
   |----------|----------|------------|----------|
   | feature | yes | yes | if system-level |
   | greenfield | yes | yes | yes |
   | migration | yes | yes | if architecture changed |
   | refactor | only if architecture changed | no | no |
   | bug-fix | no | no | no |

3. **Execute applicable subcommands** in order:
   - `tech` (if applicable)
   - `guide` (if applicable)
   - Shared doc updates (commands/index.md, workflows/)
   - `overview` (if applicable — only when the build touched system-level patterns)

4. **Spec-graph routing** (if `docs/spec-graph.json` exists):
   - Read spec-graph.json
   - Find nodes whose `impl_files` overlap with `git diff --name-only main...HEAD`
   - For each matched node, check if it has `guide_files`, `arch_files`, or `ref_files`
   - Flag these as "docs that may need updating" — show to user, don't auto-edit

5. **Report summary:**
   ```
   ## Docs Generated
   - Tech doc: docs/architecture/features/{slug}.md (new)
   - User guide: docs/guide/features/{slug}.md (new)
   - Commands index: updated (added /brana:docs row)
   - Philosophy: no update needed
   - Spec-graph routing: 2 related docs flagged for review
   ```

---

## Composability

This skill is designed to be invoked by other skills:

```
# From /brana:build CLOSE step:
Skill(skill="brana:docs", args="all {task-id}")

# From /brana:reconcile (after spec changes):
Skill(skill="brana:docs", args="tech {task-id}")

# Manual:
/brana:docs guide t-476
```

When invoked programmatically (by another skill), skip AskUserQuestion prompts for existing doc updates — auto-generate new docs, only prompt for shared doc modifications.

---

## Spec-Graph Routing

When `docs/spec-graph.json` exists and nodes have doc routing fields (`guide_files`, `arch_files`, `ref_files`), use them to discover which docs need updating:

1. Get changed files: `git diff --name-only main...HEAD`
2. For each changed file, find spec-graph nodes where `impl_files` contains it
3. Collect all `guide_files`, `arch_files`, `ref_files` from matched nodes
4. These are candidate docs for updating

**Graceful degradation:** If spec-graph.json doesn't exist or nodes lack routing fields, fall back to convention-based matching (feature slug in docs/guide/features/ and docs/architecture/features/).

---

## Rules

1. **Templates are the source of truth** for doc structure. Always use `system/skills/build/templates/tech-doc.md` and `user-guide.md`.
2. **Never auto-edit workflow docs** — too much coherence risk. Flag them for the user.
3. **Diff preview before updating existing docs** — show what would change, get approval.
4. **Philosophy.md grows incrementally** — append insights, don't rewrite.
5. **Bug fixes skip docs entirely** — the fix is in the code, the test documents the behavior.
6. **"Shipped without docs means not shipped"** — but this skill doesn't enforce that. CLOSE does. This skill just generates.
