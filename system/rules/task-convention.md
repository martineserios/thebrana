# Task Convention

## Before branching

1. Read `.claude/tasks.json`. State what you found.
2. Task exists → use its branch convention, set `in_progress`.
3. No task → propose one before branching.

After completing: update task to `completed` with notes.

Fields: id, subject, description, tags, status, stream, type, parent, priority, effort, execution, blocked_by, branch, github_issue, created, started, completed, notes, context, strategy, build_step. Types: ph-/ms-/t-/st-. Status: pending/in_progress/completed/cancelled. Streams: roadmap/bugs/tech-debt/docs/experiments/research/maintenance. Strategy: auto-classified from description.

Reads: free. Writes: confirm first.

Branch: roadmap=feat/, bugs=fix/, tech-debt=refactor/, docs=docs/, research=research/, maintenance=chore/. Format: `{prefix}{id}-{slug}`.

```
Task t-015 (stream: roadmap) → branch: feat/t-015-jwt-auth
Task t-022 (stream: bugs)    → branch: fix/t-022-session-timeout
Task t-030 (stream: docs)    → branch: docs/t-030-api-contracts
```

Code tasks: `/brana:backlog start` enters `/brana:build`. Done: `/brana:build` CLOSE step. `/brana:backlog done` for manual/external only.

## Issue tracking

- Check GitHub Issues before starting new work — avoid duplicating effort
- Link commits: `fixes #N`, `relates to #N`
- Don't create issues unless asked — check existing ones first

```
Example: user says "add rate limiting" → gh issue list --search "rate limit"
→ found #42 → commit: "feat(api): add rate limiting (fixes #42)"
```
