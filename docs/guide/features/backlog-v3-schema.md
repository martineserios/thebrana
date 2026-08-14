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

The consumer landed with t-2813 (ADR-079 §2/§3): **`brana backlog wave pull wave-N`** — one atomic pull cycle: re-resolve the selector, filter `pending ∧ ac_state:approved ∧ ¬parked`, count in-flight matches against `wip_limit`, set the first eligible task `in_progress`. At-limit and none-eligible report as normal `ok` outcomes with counts (a runner beat just skips the cycle). The committed runner procedure — how to wrap `pull` in a supervised `/loop`, and the verbs a runner is denied — is [drain-loop.md](../workflows/drain-loop.md).

Two guard rails landed with t-2782 (ADR-079 §3):

- **`wip_limit`** — a nullable non-negative integer on the wave (`brana backlog wave set wave-1 wip_limit 3`, `wip_limit null` to clear). `null` (the default) means unbounded; `0` means pause pulling. It bounds how many selector-matched tasks may be `in_progress` at once, enforced at the future loop runner's pull step (t-2813) — not at `drain`, not at task `start`, so manually starting wave-matched tasks still works. There is deliberately no default number until real drain usage exists.
- **Selector/gate freeze while draining** — `wave set` refuses `selector` and `gate` edits while a wave's status is `draining` (waves have no audit log, so a mid-drain edit would silently redirect what the next pull cycle matches). Requeue first (`wave set wave-1 status queued`), edit, re-drain. Everything else (`name`, `contract`, `wip_limit`, `status` itself) stays editable while draining.

## AC approval (`ac approve`)

`ac_state` tracks whether a task's acceptance criteria are trusted: `none` → `proposed` (a loop drafted them via `ac-propose`) → `approved` (you signed off). Approval is a verb, not a field write (t-2812, ADR-079):

```bash
brana backlog ac t-123 approve
# {"ok":true,"id":"t-123","ac_state":"approved","promoted":2,"already_approved":false}
```

Approve does two things atomically: it **promotes** anything in `proposed_acceptance_criteria` into the live `acceptance_criteria` field (dedup-union — hand-authored criteria are kept, order preserved) and **flips** `ac_state` to `approved`. MCP twin: `backlog_ac_approve(task_id)`.

Rules worth knowing:

- Approving a task with no criteria in either field is an error — there's nothing to approve.
- `brana backlog set t-123 ac_state approved` (and the MCP/batch equivalents, and `add --json`) are **rejected** with a pointer to the verb — the precondition can't be bypassed.
- Editing `acceptance_criteria` on an approved task drops it back to `proposed`: approval binds to the criteria text you approved, not just the state. Re-approve after editing.
- Re-approving an approved task is a harmless no-op (`already_approved: true`).
- The verb is human-only by design: the future loop runner (t-2813) is denied it, so a loop can propose criteria but never approve its own work contract.

## Migration status

The mechanical collapse (`level` → `type`, flat `epic` → epic nodes) has a script — `system/scripts/migrate/collapse-level-epic-v3.py` — but it has **not been run against live data yet**. Until it runs:

- `level` and `epic` are sealed as write fields (you can't set them anymore — `--epic` is a deprecated no-op, a JSON payload containing `level`/`epic` is rejected)
- existing tasks still carry their old `level`/flat-`epic` values, and `active_epic` resolution/`backlog focus` fall back to reading the flat tag for compatibility
- `validate.sh` Check 63 will flag any task still carrying `level`/`epic` once the migration is expected to have run

Once the migration runs (`--write`), 1,108 previously-unparented tasks re-home under their epic node automatically; 714 tasks that already sit under a milestone/phase keep that parent and just lose the flat `epic` tag (see the tech doc for why).
