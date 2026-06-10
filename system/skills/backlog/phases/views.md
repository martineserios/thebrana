<!-- backlog phase: /brana:backlog status, roadmap, next — CLI-delegated views — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

## /brana:backlog status

High-level progress view with aggregation. Use `--all` for cross-client task-level drill-down.

**Delegate entirely to CLI. Do not read tasks.json or compute anything manually.**

### Steps

1. Run `brana backlog status` — outputs themed project status (progress bar, counts)
2. Run `brana backlog stats` — outputs JSON aggregate stats (by_status, by_state, by_stream, by_priority, by_type). `by_status` keys are raw `task.status` values (queryable via `--status`); `by_state` keys are synthetic display values (`done`, `active`, `blocked`, `parked`, `pending`).
3. Run `brana backlog next` — outputs themed next-up list (top 5 by priority)
4. Present the CLI output directly to the user. Do not reformat or recompute.

### Cross-client view (`--all`)

Run `brana backlog status --all` — CLI handles portfolio aggregation, theming, and rendering.

For JSON output (when you need to process data): `brana backlog status --all --json`

### Additional detail (optional, only if user asks)

- Blocked chains: `brana backlog blocked`
- Stream breakdown: already in `brana backlog stats` output
- Phase tree: `brana backlog roadmap`
- Specific phase subtree: `brana backlog tree <phase-id>`

---

## /brana:backlog roadmap

Full tree view — every level expanded.

**Delegate entirely to CLI. Do not read tasks.json or build trees manually.**

### Steps

1. Run `brana backlog roadmap` — outputs themed full tree (phases -> milestones -> tasks with icons, progress bars, blocked indicators)
2. Present the CLI output directly to the user. Do not reformat.

For JSON output: `brana backlog roadmap --json`
For a subtree: `brana backlog tree <phase-or-milestone-id>`

---

## /brana:backlog next

Find the highest-priority unblocked task.

**Delegate entirely to CLI.**

### Steps

1. Run `brana backlog next` — outputs themed top-5 list sorted by priority
2. Present the CLI output directly.

Optional filters (pass through to CLI):
- By tag: `brana backlog next --tag scheduler`
- By stream: `brana backlog next --stream dev` or `--stream research`

---

