# Feature: Research Stream in /tasks

## Goal

Make `research` a first-class task stream so research URLs (previously in `docs/backlog-urls.md`) live in `tasks.json` with full cross-referencing, promotion, and triage capabilities.

## Design Decisions

1. **URLs in `context` field** — format: `URL: {url} | Author: {author} | Source tier: {tier} | Original: #{num}`
2. **Regular `t-NNN` IDs** — no special prefix; promotion = change stream, no ID renumbering
3. **No new subcommand** — extend existing `/tasks add`, `/tasks status`, `/tasks next`
4. **Research tasks are flat** — no parent/milestone hierarchy, `execution: code` (Claude does the research)
5. **URL auto-detection** — `/tasks add` suggests `stream: research` when description contains `https://`
6. **Branch prefix** — `research/` for research tasks that produce code artifacts
7. **Cross-reference on add** — when adding any non-research task, scan research tasks for tag overlap and surface matches

## Promotion Workflow

Research tasks start as `stream: research`, `execution: code`, `status: pending`.

To promote a research task to actionable work:
1. Review the research (`/tasks start <id>` → read, evaluate, extract patterns)
2. Complete the research task with notes summarizing findings
3. If actionable: create a new task in the appropriate stream (roadmap/bugs/tech-debt) with a reference to the research task in context

## Status Rendering

`/tasks status` shows a Research section after Tech Debt:

```
Research                          5 new · 2 reviewed · 1 applied
├── → t-105 GraphRAG evaluation           pending [knowledge-graphs]
└── ...(+62 more)
```

Research triage counts: `new` = pending, `reviewed` = completed with notes, `applied` = completed and spawned follow-up task.

## Migration

69 URLs from `docs/backlog-urls.md` migrated to `.claude/tasks.json`:
- IDs: t-091 through t-159
- 8 reviewed items → `status: completed` with review notes
- 61 new items → `status: pending`
- Source file marked as superseded

## Files Changed

| File | Change |
|------|--------|
| `system/rules/task-convention.md` | Add `research` stream, `research/` branch prefix |
| `system/skills/tasks/SKILL.md` | URL auto-detect in `/tasks add`, research section in `/tasks status`, `--stream` filter in `/tasks next`, cross-reference scan |
| `system/rules/delegation-routing.md` | Add research task trigger |
| `.claude/tasks.json` | 69 research tasks (t-091 through t-159) |
| `docs/backlog-urls.md` | Superseded notice |
