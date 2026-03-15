---
name: docs
description: "Update living documentation — user guide, tech docs, and philosophy overview. Auto-triggered by /brana:build CLOSE or called standalone. Uses spec-graph to detect affected docs."
argument-hint: "[guide|tech|overview|reference|all]"
group: brana
depends_on:
  - build
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# Docs

Update the three living documentation layers based on what changed in the codebase.
Composable building block — called by `/brana:build` CLOSE, `/brana:reconcile`, or standalone.

## Three Doc Layers

| Layer | Location | Audience | Updated by |
|-------|----------|----------|------------|
| **User Guide** | `docs/guide/` | End users | `guide` subcommand |
| **Tech Docs** | `docs/architecture/` | Contributors | `tech` subcommand |
| **Philosophy** | `docs/guide/philosophy.md` | Everyone | `overview` subcommand |
| **Reference** | `docs/reference/` | Everyone | `reference` subcommand (deterministic) |

## Boundary Rules

- **guide/** — HOW to use. Task-oriented workflows. No internals.
- **architecture/** — HOW it works. Contributor-facing design. No per-component catalogs.
- **reference/** — WHAT exists. Deterministic catalog from frontmatter. No narrative.

## Commands

- `/brana:docs guide` — update user guide docs affected by recent changes
- `/brana:docs tech` — update architecture/contributor docs
- `/brana:docs overview` — refresh philosophy.md
- `/brana:docs reference` — regenerate reference docs from frontmatter (deterministic)
- `/brana:docs marketplace` — sync marketplace.json, README, CHANGELOG with system state
- `/brana:docs all` — run all five in sequence

---

## How It Works

### 1. Detect affected docs (all subcommands except `reference`)

Query `docs/spec-graph.json` for changed files:

```bash
# Get changed files (context-dependent)
# Called from CLOSE: git diff from task branch
# Called standalone: git diff HEAD~5..HEAD or user-specified range
git diff --name-only HEAD~1..HEAD
```

For each changed file, look up its node in spec-graph.json:
- `guide_files` → affected user guide docs
- `arch_files` → affected architecture docs
- `ref_files` → affected reference docs

If no spec-graph hits, skip silently.

### 2. Update affected docs

For each affected doc:

1. **Read** the current doc content
2. **Read** the changed source files (impl, skill, hook, agent, etc.)
3. **Compare** — identify sections that are stale based on the changes
4. **Update** — rewrite stale sections while preserving structure and tone
5. **For shared docs** (system-level, not per-feature): show a diff preview before writing

### 3. Reference subcommand (deterministic)

Runs `system/scripts/generate-reference.py` — no LLM involvement:

```bash
uv run python3 system/scripts/generate-reference.py
```

Generates `docs/reference/skills.md`, `agents.md`, `hooks.md`, `rules.md`, `commands.md` from source frontmatter.

---

## /brana:docs guide

Update user-facing docs in `docs/guide/`.

### Steps

1. **Identify affected guide files** from spec-graph `guide_files` field
2. **For each affected file:**
   - Read current content
   - Read changed source (skill SKILL.md, workflow, etc.)
   - Update: command syntax, options, examples, workflow descriptions
   - Preserve tone (conversational, task-oriented)
3. **New skill/workflow with no guide doc:** create from template
   - Workflow docs: `docs/guide/workflows/{skill-name}.md`
   - Command docs: update `docs/guide/commands/index.md`
4. **Diff preview** for existing shared docs (new files auto-commit)

### What to update

- Command syntax and options (from SKILL.md frontmatter)
- Workflow steps (from SKILL.md body)
- Examples (regenerate if API changed)
- Cross-references to other skills

### What NOT to update

- Philosophy or design rationale (that's `overview` or `tech`)
- Per-component catalogs (that's `reference`)
- Internal architecture details (that's `tech`)

---

## /brana:docs tech

Update contributor docs in `docs/architecture/`.

### Steps

1. **Identify affected arch files** from spec-graph `arch_files` field
2. **For each affected file:**
   - Read current content
   - Read changed source (hooks, agents, scripts, etc.)
   - Update: design descriptions, component relationships, extending guides
   - Preserve tone (technical, contributor-oriented)
3. **New component with no arch doc:** add a section to the relevant overview file
4. **Diff preview** for existing shared docs

### What to update

- Component design descriptions
- Integration points and dependencies
- Extending guides (how to add a new skill/hook/agent)
- Architecture diagrams (if structure changed)

### What NOT to update

- Per-component catalogs (that's `reference`)
- User-facing workflows (that's `guide`)
- Feature briefs (those are created by `/brana:build` CLOSE step 6)

---

## /brana:docs overview

Refresh `docs/guide/philosophy.md`.

### Steps

1. Read current philosophy.md
2. Read recent changes (from git log or task context)
3. Check if any changes affect core system behavior:
   - New enforcement mechanism (hook, rule)
   - New learning loop (memory, pattern extraction)
   - Changed system architecture (layers, deployment)
4. If yes: update the relevant section of philosophy.md
5. If no: skip — philosophy doesn't change on every build

### When it matters

This subcommand only produces changes when something fundamental shifts.
Most builds won't touch it. That's correct — the philosophy is stable.

---

## /brana:docs reference

Regenerate reference docs deterministically.

### Steps

1. Run `uv run python3 system/scripts/generate-reference.py`
2. If `--check` mode (CI): exit 1 if any files would change
3. Report which files were updated

No LLM involvement. Output is deterministic from source frontmatter.

---

## /brana:docs marketplace

Update plugin marketplace-compatible docs. Keeps `marketplace.json`, repo README,
and CHANGELOG in sync with the actual system state.

### Steps

1. **Update `system/.claude-plugin/marketplace.json`:**
   - Count skills: `ls system/skills/` (exclude `_shared`, `acquired`)
   - Count hooks: parse `system/hooks/hooks.json` + count bootstrap PostToolUse hooks
   - Count agents: `ls system/agents/*.md`
   - Update `features` array with accurate counts
   - Update `version` if semver bump detected (from plugin.json)
   - Update `compatibility.claude_code` if minimum CC version changed

2. **Update repo README** (root `README.md` if it exists):
   - Sync install instructions from `marketplace.json`
   - Sync feature list
   - Sync skill count and names from reference
   - Keep custom content (intro, contributing, license) untouched

3. **Update CHANGELOG.md** (if it exists):
   - Append entry for current version if not already present
   - Pull from git log since last version tag
   - Format as Keep a Changelog sections (Added, Changed, Fixed, Removed)

### What it syncs

| Source | Target | Field |
|--------|--------|-------|
| `system/skills/` count | `marketplace.json` features[0] | skill count |
| `system/hooks/hooks.json` + bootstrap | `marketplace.json` features[1] | hook count |
| `system/agents/` count | `marketplace.json` features[2] | agent count |
| `system/.claude-plugin/plugin.json` version | `marketplace.json` version | semver |
| `marketplace.json` | `README.md` | install, features |

---

## /brana:docs all

Run all five subcommands in sequence: `reference` → `marketplace` → `guide` → `tech` → `overview`.

Reference runs first because guide and tech may link to reference docs.
Marketplace runs second to sync counts before guide references them.

---

## Integration with /brana:build CLOSE

When called from CLOSE (post-merge follow-up):

1. CLOSE completes merge to main
2. CLOSE invokes `/brana:docs all` as a follow-up
3. `/brana:docs` runs in the current context (no fresh agent — has all build context)
4. Doc updates commit on main with message: `docs: update living docs after {task-id}`

### Data available from CLOSE

- Task ID and metadata (subject, description, tags, strategy)
- Changed files (git diff)
- Design decisions from SPECIFY/PLAN steps
- Commit messages from BUILD step

---

## Standalone Usage

When called outside of CLOSE:

```
/brana:docs all                    — full doc pass
/brana:docs guide                  — user guide only
/brana:docs reference              — regenerate reference catalogs
/brana:docs tech                   — architecture docs only
/brana:docs overview               — philosophy refresh (rare)
```

Standalone mode uses `git diff HEAD~5..HEAD` to detect changes (adjustable).
If no changes detected, reports "docs up to date" and exits.
