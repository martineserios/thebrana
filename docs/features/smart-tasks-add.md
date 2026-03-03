# Feature: Smart /tasks add with dependency scan

**Date:** 2026-03-03
**Status:** designing

## Goal
When adding a task via `/tasks add`, the system suggests tags, effort, parent milestone, and dependency candidates by cross-referencing existing pending tasks. User confirms each suggestion. No auto-priority, no auto-commit of dependencies. Additionally, migrate doc 30's pending backlog items into tasks.json as a one-time operation.

## Audience
Solo developer using brana's `/tasks` skill to manage backlogs across projects.

## Constraints
- Skill is pure markdown (SKILL.md) — no bundled scripts yet (t-045 pending)
- Must work with Claude's native tools (Read, Write, Bash, Grep) — no external dependencies
- Challenge corrections from PM literature must be respected:
  - No auto-priority (priority is a strategic choice, not algorithmic)
  - Dependencies are suggestions labeled "possible — confirm?", never auto-committed
  - Build-trap detection: flag solution-language tasks without outcome context
- Backward compatible — existing `/tasks add` behavior preserved, intelligence is additive

## Scope (v1)

### Smart /tasks add enhancement
- **Tag suggestion**: Extract keywords from description, match against existing tag vocabulary
- **Effort suggestion**: Estimate from description length/complexity (S/M/L)
- **Parent suggestion**: Match against active milestones by keyword/tag overlap
- **Dependency scan**: Cross-reference pending tasks by tag overlap (2+ shared tags) and keyword match in subjects. Present as "possible dependency — confirm?"
- **Build-trap check**: If description contains solution language ("build", "implement", "create", "add") without outcome/problem context, optionally prompt "What problem does this solve?" and store in `context` field

### Doc 30 migration (one-time)
- Map pending items to tasks.json entries (skip items already migrated)
- Mark migrated items in doc 30 as `done (migrated to tasks.json)`
- Research leads section: leave as-is (not actionable tasks, already triaged to dimension docs)
- Deferred items: migrate with appropriate status/notes

## Deferred
- Auto-priority / ICE scoring (future automation dial)
- Duplicate detection via embeddings (needs claude-flow, separate task)
- `/tasks groom` command (separate feature)
- `/tasks dump` brain-dump mode (separate feature)
- Discovery stream (needs broader workflow design)
- URL/platform-name research trigger via scout agent

## Research findings

### From PM literature challenge (NLM-grounded, 10 books)
1. **Over-automation risk** (Cagan, LeMay): Auto-triage removes deliberate friction needed to evaluate worth. Smart defaults + human confirmation is the correct pattern.
2. **Priority is strategic** (Perri, Croll): Cannot be inferred algorithmically. Leave null, user sets manually.
3. **Dependencies need confirmation** (Fitzpatrick): Keyword matching is superficial text, not structural reality. Suggest, never auto-commit.
4. **Build-trap signal** (Perri): Flag tasks describing solutions without outcome context.
5. **Extensibility**: Each suggestion step is independent — can be automated progressively (ask → auto-accept-if-confident → auto-accept-always).

### From /tasks SKILL.md analysis
- Current add flow: 7 steps (parse → read → ask stream → ask milestone → ask tags → auto-ID → confirm)
- Enhancement adds 4 new steps between tag assignment and confirmation
- Existing flows (`/tasks start`, `/tasks execute`, `/tasks portfolio`) already check blocked_by — no changes needed there

## Open questions
None — design corrected by challenge, approach chosen (suggest-only).
