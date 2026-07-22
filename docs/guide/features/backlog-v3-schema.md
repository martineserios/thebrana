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

An epic also carries a `wip_limit` (default 10). Adding an 11th open task under an epic doesn't block the add — it prints an advisory warning:

```
⚠ epic in-002 is at its WIP cap (10/10 open) — adding this task makes 11; consider closing or parking before adding more
```

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

## Wave (minimal, storage-only)

A `wave` is a named record — not yet a working queue. This lands the storage shape and CRUD only; resolving a wave's `selector` against the task list (`backlog wave drain`, the intent-CLI query grammar) is future work.

```bash
brana backlog wave add --name v3-w1 --selector "shape:mechanical ac_state:approved" --contract "all tests green"
brana backlog wave list
brana backlog wave get wave-1
brana backlog wave set wave-1 status draining
```

Status is `queued` → `draining` → `shipped`, but nothing enforces that ordering yet — you can set any status at any time.

## Migration status

The mechanical collapse (`level` → `type`, flat `epic` → epic nodes) has a script — `system/scripts/migrate/collapse-level-epic-v3.py` — but it has **not been run against live data yet**. Until it runs:

- `level` and `epic` are sealed as write fields (you can't set them anymore — `--epic` is a deprecated no-op, a JSON payload containing `level`/`epic` is rejected)
- existing tasks still carry their old `level`/flat-`epic` values, and `active_epic` resolution/`backlog focus` fall back to reading the flat tag for compatibility
- `validate.sh` Check 63 will flag any task still carrying `level`/`epic` once the migration is expected to have run

Once the migration runs (`--write`), 1,108 previously-unparented tasks re-home under their epic node automatically; 714 tasks that already sit under a milestone/phase keep that parent and just lose the flat `epic` tag (see the tech doc for why).
