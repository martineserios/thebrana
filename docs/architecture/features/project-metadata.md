# Feature: Project-Level Metadata

**Date:** 2026-03-09
**Status:** planning
**Task:** t-287

## Problem

After the clients rename (t-281), `tasks-portfolio.json` has a nested `clients[].projects[]` structure, but:
- Tasks don't know which project they belong to — no `project` field
- Portfolio/status views show client slug only, not project
- Projects have no canonical metadata at the thebrana level (id, type, stage)
- `/brana:onboard` and `/brana:align` create project structure but don't register it in the portfolio

## Decision Record (frozen 2026-03-09)
> Do not modify after acceptance.

**Context:** The portfolio registry (`tasks-portfolio.json`) holds `{ slug, path }` per project but no richer metadata. Tasks reference their project only implicitly (by which file they live in). Multi-project clients don't exist yet but the schema supports them.

**Decision:**
1. Enrich `tasks-portfolio.json` project entries with metadata (type, stage, tech_stack, created date)
2. Do NOT add `project` field per-task — tasks know their project from file location (path → portfolio lookup at read time)
3. Update portfolio/status/roadmap views to show project name when relevant (injected at read time)
4. Have onboard/align register projects in the portfolio automatically (deferred: t-288)

**Consequences:**
- Portfolio registry becomes the single source of project metadata
- Views inject project context at read time — no per-task sync obligation
- Onboard becomes the canonical project registration point (deferred)
- No migration/backfill needed

## Constraints

- Backward compatible — legacy flat `tasks-portfolio.json` fallback preserved
- No breaking changes to existing skill behavior
- New metadata fields are optional (null default) — existing entries work without them
- `stage` is advisory, updated via `/brana:review monthly` — not authoritative

## Scope

### Part 1: Enriched project registry (tasks-portfolio.json)

Add metadata to project entries:
```json
{
  "clients": [{
    "slug": "nexeye",
    "projects": [{
      "slug": "eyedetect",
      "path": "~/enter_thebrana/projects/nexeye_eyedetect",
      "type": "code",
      "stage": null,
      "tech_stack": ["docker", "swarm", "python"],
      "created": "2026-01-15"
    }]
  }]
}
```

New fields on `projects[]`:
- `type` (code/venture/hybrid) — detected by onboard, rarely changes
- `stage` (discovery/validation/growth/scale, null for code-only) — advisory, reviewed monthly
- `tech_stack` (array of strings) — named distinctly from task-level `tags` to avoid collision
- `created` (date registered)

### Part 2: View updates

Portfolio and status views show project when client has multiple projects:
- Multi-project: `nexeye/eyedetect`, `nexeye/lens-api`
- Single-project: `nexeye` (no redundancy)
- Wide mode: `Project` column always visible
- Unified view: `client/project` prefix

Project context is injected at **read time** from the portfolio registry — no per-task field needed.

### Part 3: Schema documentation

- Update `docs/architecture/features/tasks-portfolio.md` with enriched schema shape
- Document the nested JSON schema explicitly (gap flagged in t-281)
- Update `task-guide.md` portfolio section

### Deferred (separate task)

Auto-registration via `/brana:onboard` and `/brana:align` — t-288.

## Research

- Current portfolio has 4 clients, each with 1 project
- Onboard skill is diagnostic-only (doesn't write to portfolio)
- Align skill creates project structure but doesn't register in portfolio
- CWD → project lookup: `git rev-parse --show-toplevel` → match against `tasks-portfolio.json` paths

## Challenger findings

1. **Per-task `project` field dropped** (critical). Tasks know their project from file location. Adding the field creates sync obligation and slug collision risk. Project context injected at read time instead.
2. **Renamed `tags` → `tech_stack`** (warning). Avoids collision with task-level `tags` field name.
3. **`stage` goes stale** (warning). Tied to `/brana:review monthly` cadence. Documented as advisory.
4. **Auto-registration deferred** (observation). Correct split — onboard changing from diagnostic to write-capable deserves its own review.
5. **Root-level `project` on tasks.json** already exists for thebrana. Could extend to client projects as a lighter pattern than per-task fields — but not needed for v1.
