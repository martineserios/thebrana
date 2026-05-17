---
always-load: true
---
# Task Convention

## Before branching

1. Read `.claude/tasks.json`. State what you found.
2. Task exists → use its branch convention, set `in_progress`.
3. No task → propose one before branching.

After completing: update task to `completed` with notes.

Fields: id, subject, description, tags, status, kind, stream (deprecated), type, parent, priority, effort, execution, blocked_by, branch, github_issue, created, started, completed, notes, context, strategy, build_step. Types: in-/ph-/ms-/t-/st-. Status: pending/in_progress/completed/cancelled. Kind (v2): feature/fix/refactor/research/docs/design/ops. Strategy: auto-classified from description.

Reads: free. Writes: confirm first.

Branch: feature=feat/, fix=fix/, refactor=refactor/, docs=docs/, research=research/, ops=chore/. Format: `{prefix}{id}-{slug}`.

```
Task t-015 (kind: feature) → branch: feat/t-015-jwt-auth
Task t-022 (kind: fix)     → branch: fix/t-022-session-timeout
Task t-030 (kind: docs)    → branch: docs/t-030-api-contracts
```

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
