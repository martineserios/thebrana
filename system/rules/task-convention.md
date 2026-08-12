---
always-load: true
---
# Task Convention

Work-start ordering: see `work-start.md`.

After completing: update task to `completed` with notes.

Fields: id, subject, description, tags, status, kind, type, parent, priority, effort, execution, blocked_by, branch, github_issue, created, started, completed, notes, context, strategy, build_step. Types: in-/ph-/ms-/t-/st-. Status: pending/in_progress/completed/cancelled. Kind (v2): feature/fix/refactor/research/docs/design/ops. Strategy: auto-classified from description.

Cancelling a parent task does NOT auto-cancel children. When cancelling a parent, manually cancel or re-parent all children. `brana backlog tree <parent-id>` shows the subtree.

Reads: free. Writes: confirm first.

Branch prefix: keyed on `kind` (authoritative — it names what the change does); falls back to `work_type` only when `kind` is absent (22% of tasks). The mapping and the shared `resolve_branch_prefix()` live in `system/skills/_shared/branch-prefix.md` — the single authority. Do not restate it here or in `start.md` (t-2494). Full branch format: CLAUDE.md §Branch naming.

Code tasks: `/brana:backlog start` enters `/brana:build`. Done: `/brana:build` CLOSE step. `/brana:backlog done` for manual/external only.

## AC: prefix — acceptance criteria

Lines in `context` starting with `AC:` are machine-readable acceptance criteria. `/brana:build` reads them to auto-generate a `/goal` string. Additive — tasks without `AC:` lines are unaffected.

```
context: "AC: all tests green\nAC: branch merged to main\nAC: tasks.json updated"
```

## Issue tracking

- Check GitHub Issues before starting new work — avoid duplicating effort
- Link commits: `fixes #N`, `relates to #N`
- Don't create issues unless asked — check existing ones first

```
Example: user says "add rate limiting" → gh issue list --search "rate limit"
→ found #42 → commit: "feat(api): add rate limiting (fixes #42)"
```
