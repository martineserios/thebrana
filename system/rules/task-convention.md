---
always-load: true
---
# Task Convention

Work-start ordering: see `work-start.md`.

After completing: update task to `completed` with notes.

Fields: id, subject, description, tags, status, kind, type, parent, priority, effort, execution, blocked_by, branch, github_issue, created, started, completed, notes, context, strategy, build_step, work_type, acceptance_criteria, ac_state. Types: in-/ph-/ms-/t-/st-. Status: pending/in_progress/completed/cancelled. Kind (v2): feature/fix/refactor/research/docs/design/ops. Strategy: auto-classified from description.

`epic` isn't a field (`set_field`/`add` reject it) — membership is `parent` → nearest `type:"epic"` task, resolved live, no cache. See: [backlog-v3-schema.md](../../docs/architecture/features/backlog-v3-schema.md).

**ADR-086:** task = one context window, wave = one AFK cycle (§1); no new `phase`/`milestone` — CLI warns, use epic+`parent` (§9); appends = pointer-not-paste (§7).

Cancelling a parent does NOT auto-cancel children — manually cancel/re-parent. `brana backlog tree <parent-id>` shows the subtree.

Reads free; writes confirm first.

Branch prefix: `kind` authoritative, `work_type` fallback (22% lack `kind`). Resolver: `system/skills/_shared/branch-prefix.md` (single authority, t-2494). Format: CLAUDE.md §Branch naming.

Code tasks: `/brana:backlog start` enters `/brana:build`; done via its CLOSE step. `/brana:backlog done` is manual/external only.

## AC: prefix — acceptance criteria

Lines in `context` starting with `AC:` are machine-readable acceptance criteria — `/brana:build` reads them to auto-generate a `/goal` string. Additive; unaffected without them.

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
