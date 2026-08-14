# brana backlog v2 schema

> Brainstormed 2026-05-13. Status: idea.

## Problem

The brana backlog schema grew organically and now has three overlapping classification dimensions (`stream`, `type`, `tags`). This causes:
- Unclear assignment: "should this be `stream=roadmap` or `stream=tech-debt`?"
- Redundancy: `stream=bugs` AND `type=bug` AND `tags=["bug"]` can all mean the same thing
- `brana backlog focus/next` surfaces noise because stream categorization is inconsistent
- No structural "initiative" level above phases — initiatives are currently encoded as tags (`agent-v4`, `anita-v2`), which works but isn't queryable or hierarchically visible
- No clean mapping to Linear's full hierarchy (Initiative → Project → ProjectMilestone → Issue)

## Proposed solution

### 1. New 4-level hierarchy

```
in-XXX  initiative      → Linear Initiative        (new)
ph-XXX  phase        → Linear ProjectMilestone  (existing)
ms-XXX  milestone    → Linear Issue             (existing)
t-XXX   task         → stays in brana only      (existing)
```

An `initiative` is a multi-phase strategic goal. Examples: "The New Agent", "Platform Transition", "Business as Individual". Initiatives span many months and many phases. They map 1:1 to Linear Initiatives.

### 2. Replace `stream` with `kind`

| `kind` | Replaces `stream` | Meaning |
|--------|------------------|---------|
| `feature` | roadmap | Planned product work |
| `fix` | bugs | Defects |
| `refactor` | tech-debt | Cleanup, tech debt |
| `research` | research + experiments | Spikes, exploration, A/B |
| `docs` | docs | Documentation |
| `design` | architecture | ADRs, technical decisions |
| `ops` | maintenance | Infrastructure, deployment |

**Rule:** `kind` = what type of work. `tags` = what it's about. No overlap.

`brana backlog next --kind feature` = "what feature should I build next?"
`brana backlog next --kind fix` = "what bugs need fixing?"

### 3. Linear sync — 3 passes

```
Pass 1: in-XXX → initiativeCreate  → stores linear_initiative_id
Pass 2: ph-XXX → projectMilestoneCreate (within tagged project)  → stores linear_milestone_id
Pass 3: ms-XXX → issueCreate (with projectMilestoneId)  → stores linear_issue_id
t-XXX  → stays in brana only
```

Config-driven project routing stays via `tag_project_map` in `linear-sync-config.json`.

> Scope note: Linear sync is proyecto_anita only. `brana backlog sync` (GitHub) is universal across all projects and targets t-XXX tasks — these two syncs are independent and non-overlapping.

## What stays the same

- `priority` (P0/P1/P2/P3) — unchanged
- `effort` (S/M/L) — unchanged
- `tags` — free-form, semantic classification — unchanged
- `parent` — hierarchy link — unchanged
- `blocked_by` — dependency tracking — unchanged
- `status` (pending/in_progress/completed/cancelled) — unchanged
- ID prefix conventions (ph-/ms-/t-) — unchanged, add in-

## Migration plan

1. **CLI changes:**
   - Add `Initiative` to `TaskType` enum
   - Add `--kind` flag to `add`, `next`, `query`, `focus` (alongside or replacing `--stream`)
   - Keep `--stream` as deprecated alias during transition
   - Update `sync_linear.rs` for 3-pass logic with initiative creation

2. **Schema migration (batch script):**
   ```
   stream=roadmap      → kind=feature
   stream=tech-debt    → kind=refactor
   stream=bugs         → kind=fix
   stream=research     → kind=research
   stream=experiments  → kind=research
   stream=docs         → kind=docs
   stream=architecture → kind=design
   stream=maintenance  → kind=ops
   stream=personal     → remove (personal tasks belong in personal/ tasks.json)
   ```

3. **Initiative scaffolding (per project, manual):**
   - Create `in-XXX` tasks for existing implicit initiatives
   - Add `parent: in-XXX` to phases that belong to those initiatives
   - Update `linear-sync-config.json` with no changes needed (tags still drive project routing)

## Data snapshot (2026-05-13)

| Project | ph | ms | t | Implicit initiatives |
|---------|----|----|---|-------------------|
| thebrana | 7 | 34 | 1322 | "Business as Individual" (ph-005), "brana CLI" |
| proyecto_anita | 8 | 16 | 756 | "The New Agent" (agent-v4: 220t), "Platform Transition" (anita-v2: 91t) |

## Risks

- `stream` → `kind` migration touches filters in CLI, skills, and `brana backlog focus` output — regression risk if not done atomically
- Adding `in-XXX` requires re-parenting existing `ph-XXX` tasks — low volume but manual judgment
- `brana backlog sync --linear` 3-pass logic must handle partial sync gracefully (phases may exist before initiatives, etc.)

## Next steps

1. ADR in thebrana for `kind` field and `initiative` type (spec-first)
2. Implement `kind` in CLI (`--stream` deprecated alias)
3. Batch migration script for existing tasks
4. Add `Initiative` type + `in-XXX` ID prefix to brana
5. Scaffold initiatives in proyecto_anita and thebrana
6. Update `sync_linear.rs` for 3-pass initiative sync
