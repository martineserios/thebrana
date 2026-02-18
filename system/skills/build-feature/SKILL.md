---
name: build-feature
description: "Guide a feature from zero to shipped — research, brainstorm, design, plan, build, close. Works for any project and any kind of work (code, design, infra, venture, process). Use when building a new feature, capability, or deliverable in any project."
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Task
  - WebSearch
  - WebFetch
---

# Build Feature

Guide a feature from zero to shipped in 7 phases: orient, discover, shape, design, plan, build, close. Works for any project and any kind of work — code features, landing pages, infrastructure, venture tasks, process overhauls.

## When to use

When building a new feature, capability, or deliverable in any project. Not for brana's own roadmap phases (use `/build-phase`) or business milestones (use `/venture-phase`).

**Invocation:**
- `/build-feature` — ask what to build
- `/build-feature landing page for tinyhouse` — start with context
- `/build-feature add auth to the API` — start with a code feature
- `/build-feature CI/CD pipeline` — infrastructure work

## Process

```
Phase 0: Orient     — what project, what feature, what type?
Phase 1: Discover   — research project docs + web + cross-project memory
Phase 2: Shape      — interactive brainstorm -> persisted feature brief
Phase 3: Design     — technical architecture + ADR + challenger review
Phase 4: Plan       — task breakdown -> GitHub Issues
Phase 5: Build      — execute loop (implement -> verify -> commit -> mini-debrief)
Phase 6: Close      — validate, full debrief, merge, store learnings
```

---

## Phase 0: Orient

### 0a: Parse arguments

Read `$ARGUMENTS` for the feature description:
- If provided (e.g., `landing page for tinyhouse`), use it as the starting context
- If empty, ask the user: "What do you want to build?"

### 0b: Detect project context

Read project signals from CWD:
- `CLAUDE.md` or `.claude/CLAUDE.md` — project identity, conventions, commands
- `package.json` / `pyproject.toml` / `Cargo.toml` / `go.mod` — stack and dependencies
- `docs/decisions/` — existing ADRs (determines whether Phase 3 creates one)
- `README.md` — project purpose and structure
- `docs/features/` — existing feature briefs (naming convention, format)

Run `git rev-parse --show-toplevel` to confirm project root. Use CWD as fallback.

### 0c: Classify feature type

Based on the description and project context, classify:

| Type | Signal | Phase weight |
|------|--------|-------------|
| `code` | Source files, APIs, components | Design + Build heavy |
| `design` | UI, UX, layouts, branding | Shape heavy |
| `venture` | Business process, ops, growth | Shape + Plan heavy |
| `infra` | CI/CD, deploy, monitoring | Design heavy |
| `process` | SOPs, workflows, documentation | Shape + Plan heavy |
| `mixed` | Multiple types | Balanced |

The classification informs which phases get more attention but **never skips phases**.

### 0d: Check GitHub Issues

```bash
gh repo view --json hasIssuesEnabled 2>/dev/null
```

If issues are enabled, Phase 4 creates them. If not (no remote, issues disabled, `gh` unavailable), Phase 4 falls back to a printed task list.

---

## Phase 1: Discover

Three parallel research tracks. Spawn agents for tracks 2 and 3 while running track 1 directly.

### Track 1: Project docs (run directly)

Search the project for relevant context:
- Grep for keywords related to the feature
- Read related source files, ADRs, README sections
- Check CLAUDE.md conventions that constrain the implementation
- Note existing patterns the feature should follow

Organize findings by relevance: directly related > tangentially related > background context.

### Track 2: Web research (spawn scout agent)

Spawn a `scout` agent with WebSearch scoped by:
- Feature description from Phase 0
- Tech stack detected from project files
- Specific questions: best practices, inspiration, competitor analysis, technical approaches

The scout returns structured findings. Don't duplicate its work in main context.

### Track 3: Cross-project memory (spawn memory-curator agent)

Spawn a `memory-curator` agent to search for patterns from other portfolio projects:
- Similar features built elsewhere
- Stack-specific patterns (e.g., "Supabase auth" patterns from another project)
- Lessons learned from related work

If the agent is unavailable, fall back to manual search:

```bash
CF=""
for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
    [ -x "$candidate" ] && CF="$candidate" && break
done
[ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"
[ -z "$CF" ] && command -v npx &>/dev/null && CF="npx claude-flow"

[ -n "$CF" ] && cd "$HOME" && $CF memory search --query "{feature keywords}" --format json 2>/dev/null || true
```

Also check auto memory at `~/.claude/projects/*/memory/MEMORY.md` for relevant notes.

### Present findings

Consolidate all three tracks into a brief summary. Then ask:

> "Anything else you want me to research before we brainstorm?"

Wait for the user's answer before proceeding.

---

## Phase 2: Shape (interactive brainstorm -> feature brief)

### 2a: Interactive conversation

Discuss with the user naturally — don't rush to structure:

- **Goals** — what does success look like?
- **Audience** — who is this for?
- **Constraints** — timeline, budget, tech constraints, non-negotiables
- **Scope** — what's in v1, what's deferred?
- **Edge cases** — what could go wrong?
- **Inspiration** — what from Phase 1 resonated?

Keep the conversation flowing. Let the user think out loud. Ask follow-up questions. Challenge assumptions gently.

### 2b: Persist the feature brief

When the shape is clear, write a feature brief.

**Location:** `docs/features/{feature-slug}.md`
- Create `docs/features/` if it doesn't exist (ask first if `docs/` doesn't exist: "This project doesn't have a `docs/` directory. Create `docs/features/` for the feature brief, or put it somewhere else?")
- Slugify: lowercase, hyphens, no special chars, max 50 chars

**Format:**

```markdown
# Feature: {title}

**Date:** {YYYY-MM-DD}
**Status:** shaping

## Goal
{1-2 sentences — what does "done" look like}

## Audience
{who benefits}

## Constraints
- {constraint 1}
- {constraint 2}

## Scope (v1)
- {in scope item 1}
- {in scope item 2}

## Deferred
- {out of scope for now}

## Research findings
{key findings from Phase 1 that inform this feature}

## Open questions
{anything unresolved}
```

Show the brief to the user for approval before continuing. Update status to `designing` when approved.

---

## Phase 3: Design

### 3a: Technical design

Based on the feature brief, identify:
- Components to create or modify
- Files to touch (list specific paths)
- Patterns to follow (from project conventions and Phase 1 findings)
- Dependencies (libraries, APIs, services)
- Data flow (how information moves through the system)

Present as a concise design doc — not a novel. Focus on decisions that matter.

### 3b: ADR (if applicable)

If `docs/decisions/` exists in the project, create an ADR for the feature using the Nygard lightweight format:

```markdown
# ADR-NNN: {title}

**Date:** {YYYY-MM-DD}
**Status:** proposed

## Context
{why this decision is needed — from the feature brief}

## Decision
{the technical approach chosen}

## Consequences
{what becomes easier or harder}
```

Auto-increment the ADR number from existing files. If `docs/decisions/` doesn't exist, skip this step.

### 3c: Challenger review

Spawn a `challenger` agent to adversarially review the design:
- Surface risks and failure modes
- Identify missing edge cases
- Propose simpler alternatives
- Question assumptions

Present the design + challenger findings to the user for approval.

### 3d: Update feature brief

Update `docs/features/{feature-slug}.md`:
- Set status to `designing`
- Add a `## Design` section summarizing key decisions
- Link the ADR if one was created

---

## Phase 4: Plan (task breakdown -> GitHub Issues)

### 4a: Break down tasks

From the design, create ordered tasks:

| # | Task | Depends On | Acceptance Criteria |
|---|------|-----------|-------------------|
| 1 | {imperative title} | — | {what "done" looks like} |
| 2 | {imperative title} | #1 | {what "done" looks like} |

Rules for task breakdown:
- Titles are imperative: "Implement X", "Add Y", "Configure Z"
- Each task is small enough for one commit
- Dependencies are explicit
- Acceptance criteria are testable

### 4b: Create GitHub Issues (if available)

If GitHub Issues are available (Phase 0d check passed):

1. Create a **tracking issue** (parent):

```bash
gh issue create \
  --title "feat: {feature title}" \
  --body "Tracking issue for {feature}. See docs/features/{slug}.md for the feature brief.

## Tasks
- [ ] #{sub-issue-1}
- [ ] #{sub-issue-2}
..." \
  --label "feat/{feature-slug}"
```

2. Create **sub-issues** for each task:

```bash
gh issue create \
  --title "{task title}" \
  --body "Part of #{tracking-issue}.
Blocked by: #{dependency-issue} (if any)

## Acceptance criteria
- {criterion 1}
- {criterion 2}" \
  --label "feat/{feature-slug}"
```

3. Update the tracking issue body with actual issue numbers.

**If GitHub Issues unavailable:** print the task table as a structured list. The build loop in Phase 5 works from this list instead.

### 4c: Update feature brief

Set status to `building`. Add a `## Tasks` section linking to the tracking issue or listing the task breakdown.

### 4d: Present for approval

Show the full plan with issue links (or task list). Wait for user approval before building.

---

## Phase 5: Build (execute loop)

### 5a: Create the feature branch

Before any edits:

```bash
git checkout -b feat/{feature-slug}
```

All work happens on this branch. Main stays clean until Phase 6.

### 5b: The build loop

For each task (in dependency order):

```
1. State what you're building (reference the issue number if available)
2. Implement
3. Verify (run tests, lint, manual check — whatever's appropriate)
4. Commit: feat({scope}): {description}
   - If issue exists, add "fixes #{issue}" to close it
5. Mini-debrief (see below)
6. Move to next task
```

**At natural breakpoints** (every 2-3 tasks, or after a complex one), ask:

> "Continue to the next task, or want to review/adjust?"

### 5c: Mini-debrief (after each task)

Quick extraction — 30 seconds, not a full `/debrief`:

1. **Did anything surprise?** API that didn't work as expected, file in the wrong place, undocumented behavior.
2. **Spec mismatch?** Feature brief says X, reality requires Y.
3. **Reusable pattern?** Something worth remembering for next time.

For significant findings, store in memory:

```bash
CF=""
for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
    [ -x "$candidate" ] && CF="$candidate" && break
done
[ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"
[ -z "$CF" ] && command -v npx &>/dev/null && CF="npx claude-flow"

[ -n "$CF" ] && cd "$HOME" && $CF memory store \
  -k "build:{project}:{feature-slug}:{short-finding-id}" \
  -v '{"type": "build-learning", "feature": "{slug}", "finding": "{description}", "severity": "{low|med|high}"}' \
  --namespace patterns \
  --tags "project:{project},type:build-learning,feature:{slug}"
```

If claude-flow unavailable, append to the project's auto memory `MEMORY.md`.

Do not stop to write full documentation — collect findings, batch them in Phase 6.

---

## Phase 6: Close

### 6a: Validate

Verify all tasks complete:
- All acceptance criteria met
- Tests pass
- No regressions

```markdown
### Validation
- [x] Task 1: {title} — {how verified}
- [x] Task 2: {title} — {how verified}
- [x] All tests pass
```

If any criteria are not met, loop back to Phase 5 for those items only.

### 6b: Full debrief

Spawn the `debrief-analyst` agent with:
- Git log from branch creation to now: `git log main..HEAD --oneline`
- Mini-debrief findings collected during Phase 5
- Summary of what was built

Review its classified findings (errata / learnings / issues). Store approved learnings in memory.

If the agent is unavailable, run manually:
1. Gather evidence — git log, mini-debrief findings
2. Classify into errata / learnings / issues
3. Store findings in claude-flow memory or auto memory

### 6c: Update feature brief

Update `docs/features/{feature-slug}.md`:
- Set status to `shipped`
- Add `## Learnings` section with key findings from the debrief
- Add `## Implementation notes` with anything future maintainers should know

### 6d: Store learnings in memory

```bash
[ -n "$CF" ] && cd "$HOME" && $CF memory store \
  -k "feature:{project}:{feature-slug}:complete" \
  -v '{"type": "feature-complete", "feature": "{slug}", "date": "{YYYY-MM-DD}", "tasks": N, "learnings": N, "key_insight": "{one sentence}"}' \
  --namespace patterns \
  --tags "project:{project},type:feature-complete,feature:{slug}"
```

### 6e: Merge

Present the merge command — **do not auto-execute**:

```bash
git checkout main
git merge --no-ff feat/{feature-slug} -m "feat: {feature title}"
git branch -d feat/{feature-slug}
```

Let the user decide when to merge.

### 6f: Close tracking issue

If a GitHub tracking issue was created, close it with a summary:

```bash
gh issue close {tracking-issue-number} \
  --comment "Shipped. See docs/features/{slug}.md for brief + learnings."
```

### 6g: Report

```markdown
## Feature Complete: {title}

**Branch:** `feat/{feature-slug}`
**Date:** {YYYY-MM-DD}

### What was built
| # | Task | Commit | Verified |
|---|------|--------|----------|
| 1 | {description} | `{hash}` | {how} |
| 2 | {description} | `{hash}` | {how} |

### What was learned
- **Learnings captured:** {N} entries stored
- **Key insight:** {the single most important thing learned}

### Feature brief
`docs/features/{slug}.md` — updated with status: shipped + learnings

### Next steps
{any follow-up work, deferred items from Phase 2, or related features}
```

---

## Rules

1. **Always ask before major steps.** The plan is a proposal, not a commitment. Get approval before Phase 3 (design), Phase 4 (plan), Phase 5 (build), and Phase 6e (merge).
2. **Never skip Phase 2 (Shape).** The brainstorm is where quality decisions happen. Even for "obvious" features, spend time shaping.
3. **Feature brief is mandatory.** Persist decisions in `docs/features/` so future sessions can pick up where this one left off.
4. **One feature per invocation.** Don't build multiple features at once. Each `/build-feature` call handles one thing.
5. **Mini-debrief after every task.** Prevents losing context across long builds. Takes 30 seconds.
6. **Don't auto-merge.** Present the merge command, let the user decide.
7. **Adapt, don't gate.** Feature type informs which phases get more attention but never skips phases.
8. **Graceful degradation.** If GitHub Issues unavailable, print tasks. If claude-flow unavailable, use auto memory. If `docs/` doesn't exist, ask where to put the brief.
9. **Ask for clarification whenever needed.** A quick question saves more time than a wrong assumption.
