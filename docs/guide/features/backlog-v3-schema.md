# Backlog v3 Schema — epics, key:value tags, waves

The backlog's epic-grouping model changed (ADR-065). `epic` used to be a flat string field on every task, orthogonal to the milestone/phase tree. It's now the top of a single hierarchy: an epic is a real node with its own lifecycle, and tasks live under it via `parent`.

Two smaller, independent additions landed alongside it: key:value tags (`layer:backend`) and a minimal `wave` storage object.

## Epic lifecycle

An epic node (`type: "epic"`) has its own status vocabulary — separate from the task lifecycle:

| Task status | Epic status |
|---|---|
| pending / in_progress / completed / cancelled | active / next / parked / done / archived |

```bash
brana backlog set in-002 status active
brana backlog set in-002 status pending   # rejected — "pending" is task vocab, not epic vocab
```

Epics have no WIP cap — an epic is an unbounded grouping of "what we're building," and adding tasks under it is never limited or warned about (the `wip_limit` field and its advisory warning were retired 2026-08-12; see ADR-065's amendment). If you want to bound how much work is actively in flight, use a wave instead (below).

`blocked_by` works on epics the same way it works on tasks — an epic blocked on a prior epic stays `blocked` until that epic reaches `done` or `archived`.

## `active_epic` fails loud now

`backlog focus` (and the MCP `backlog_focus` tool) used to silently produce an unscored, no-boost view if `active_epic` (in `tasks-config.json`) didn't match anything. It now errors instead:

```bash
brana backlog focus
# {"ok":false,"error":"active_epic \"nonexistent-epic\" does not resolve to any epic node or task — ..."}
```

## key:value tags

Tags stay plain strings — no new field, no migration required. A `key:value` string is just a naming convention, and query support understands it:

```bash
brana backlog query --tag layer:backend      # exact match: only tasks tagged "layer:backend"
brana backlog query --tag layer              # any-value match: "layer:backend" AND bare "layer"
brana backlog next --tag risk:high
```

Multi-tag AND still works with mixed forms: `--tag "layer:backend,urgent"`.

## Wave (CRUD + drain)

A `wave` is a named, drainable selector over tasks. CRUD landed first (t-2315); `drain` landed 2026-08-13 (t-2775) — it enforces the `gate` and resolves the selector, but still doesn't execute anything (working the matched tasks is the loop runner's job, t-2813).

```bash
brana backlog wave add --name v3-w1 --selector "tag:wave:v3-w1" --contract "all tests green"
brana backlog wave list
brana backlog wave get wave-1
brana backlog wave drain wave-1     # gate check → match report → status: draining
brana backlog wave set wave-1 status shipped   # operator marks done (not auto-detected)
```

`drain` refuses if the wave's `gate` names a wave that isn't `shipped` yet (the error names the blocking wave; a nonexistent gate id fails loud). The MVP resolves exactly one selector form — `tag:<name>` (including key:value tags like `tag:wave:v3-w1`), matching **pending** tasks only; any other selector string is rejected with a "MVP only resolves tag:<name>" error rather than silently ignored. Draining reports the matched tasks and sets the wave's status to `draining` without touching the tasks themselves; re-draining a draining wave just re-resolves and re-reports (idempotent), while draining a `shipped` wave is an error.

Status is `queued` → `draining` → `shipped`. `drain` moves queued→draining; an operator sets `shipped` manually via `wave set`; direct `wave set` status writes remain unrestricted (any-to-any).

## Migration status

The mechanical collapse (`level` → `type`, flat `epic` → epic nodes) has a script — `system/scripts/migrate/collapse-level-epic-v3.py` — but it has **not been run against live data yet**. Until it runs:

- `level` and `epic` are sealed as write fields (you can't set them anymore — `--epic` is a deprecated no-op, a JSON payload containing `level`/`epic` is rejected)
- existing tasks still carry their old `level`/flat-`epic` values, and `active_epic` resolution/`backlog focus` fall back to reading the flat tag for compatibility
- `validate.sh` Check 63 will flag any task still carrying `level`/`epic` once the migration is expected to have run

Once the migration runs (`--write`), 1,108 previously-unparented tasks re-home under their epic node automatically; 714 tasks that already sit under a milestone/phase keep that parent and just lose the flat `epic` tag (see the tech doc for why).
