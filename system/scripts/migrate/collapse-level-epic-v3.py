#!/usr/bin/env python3
"""Collapse level/type and convert the flat epic field to hierarchy nodes in
thebrana's tasks.json (t-2312, ADR-065 backlog v3 schema migration).

Two mechanical transforms, applied in this order (per ADR-065 §Migration
engineering and t-2284's dependency sequencing -- epic values must be
consumed for re-parenting BEFORE the flat field is dropped):

  1. level -> type collapse. `type` survives on conflict (ADR-065 D8: "type
     survives -- more populated": 1,825 vs 1,254 non-null population in live
     data). `level` only backfills `type` when `type` is missing/empty.
     The `level` key is then dropped from every task, regardless of whether
     a backfill happened.

  2. epic -> node conversion. Each unique non-empty flat `epic` value gets a
     `type: "epic"` node task (reusing a pre-existing marker task if one is
     found -- see `is_epic_node_marker`). Tasks that carry that epic value
     AND have no existing `parent` are re-parented to the node. Tasks that
     already have a `parent` (a milestone/phase they were decomposed under)
     keep it -- see the module docstring section "Why parented tasks are not
     re-parented" below for why this is a deliberate, data-driven choice and
     not an oversight. The flat `epic` key is then dropped from every task,
     including the node tasks themselves.

Why parented tasks are not re-parented (open question, flagged for human
review): 714 live tasks carry BOTH a non-null `parent` and a non-empty
`epic`. Of the 166 distinct parent tasks they reference, 88 have children
that span MORE THAN ONE epic value -- i.e. `epic` is measurably orthogonal
to the existing type-tree today, not a refinement of it. Overwriting
`parent` on these 714 tasks to point straight at the epic node would
silently flatten 714 existing milestone/phase groupings (and would be lossy
for the 88 mixed-epic parents specifically -- there is no single correct
epic node to reparent the milestone itself to). This script only re-parents
tasks with NO pre-existing `parent` (1,112 in live data); already-parented
tasks lose their flat `epic` tag (mechanical retirement, per ADR-065) but
keep their structural home. Reconciling the 88 mixed-epic milestones is a
human/future-task decision, not a mechanical one -- flagged, not resolved.

Scoped to thebrana's own tasks.json only (not portfolio-wide), matching
t-2309's normalize-tags.py precedent.

Usage:
    python3 collapse-level-epic-v3.py            # dry-run (default): report only
    python3 collapse-level-epic-v3.py --write     # actually apply + write
"""
import argparse
import datetime
import json
import os
import pathlib
import subprocess
import sys

NODE_ID_PREFIX = "in-"


def find_tasks_file() -> pathlib.Path:
    """Locate this repo's tasks.json via git root, mirroring the Rust CLI's
    find_tasks_file() resolution (walk up from cwd to the nearest git root,
    then .claude/tasks.json) -- same approach as normalize-tags.py (t-2309)."""
    root = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    return pathlib.Path(root) / ".claude" / "tasks.json"


def is_tasks_file_dirty(tasks_path: pathlib.Path) -> bool:
    """True if `git status --porcelain` reports uncommitted changes to
    tasks_path specifically -- scoped to the file (per ADR-065's "refuses to
    run on a dirty tasks.json"), not a whole-repo dirty check, so unrelated
    in-flight work elsewhere in the tree doesn't block this migration.
    Dry-run never writes, so this is only consulted before --write."""
    result = subprocess.run(
        ["git", "status", "--porcelain", "--", str(tasks_path)],
        cwd=tasks_path.parent,
        capture_output=True, text=True, check=True,
    )
    return bool(result.stdout.strip())


def next_id(tasks):
    """Mirror brana-core's next_id() exactly (tasks.rs:770-777): max numeric
    suffix across all ids (regardless of prefix scheme -- in-/ph-/ms-/t-/st-
    all parse the same way), +1, always formatted as `t-{n}`."""
    best = 0
    for t in tasks:
        tid = t.get("id")
        if not tid:
            continue
        suffix = tid.rsplit("-", 1)[-1]
        try:
            n = int(suffix)
        except ValueError:
            continue
        if n > best:
            best = n
    return f"t-{best + 1}"


def resolve_type(type_value, level_value):
    """Pure function -- ADR-065 D8: `type` survives on conflict (it is the
    more populated field: 1,825 vs 1,254 non-null in live data; the only
    live conflict, t-1539, is level=milestone/type=task, resolved by keeping
    type). `level` only backfills `type` when `type` is missing/empty; a
    present, non-empty `type` is never overridden, even when it differs from
    `level`. Returns (final_type, backfilled: bool)."""
    if type_value:
        return type_value, False
    if level_value:
        return level_value, True
    return type_value, False


def collapse_level(task):
    """Mutate a single task dict in place: backfill `type` from `level` per
    resolve_type, then drop the `level` key unconditionally (if present).
    Pure aside from the in-place mutation of `task`. Returns
    (backfilled: bool, level_dropped: bool)."""
    had_level = "level" in task
    new_type, backfilled = resolve_type(task.get("type"), task.get("level"))
    if backfilled:
        task["type"] = new_type
    if had_level:
        del task["level"]
    return backfilled, had_level


def is_epic_node_marker(task):
    """Detect a pre-existing epic/initiative node task, via the `in-` id
    prefix convention (task-convention.md: id prefixes in-/ph-/ms-/t-/st-
    map to type initiative/phase/milestone/task/subtask). In live data this
    matches exactly 4 tasks (in-001..in-004), each with `type`/`level`:
    "initiative" and its own `epic` set to the slug it represents (e.g.
    in-002 epic="cc-alignment"). Deliberately NOT matched: 13 other tasks
    with `type: "initiative"` but a `t-NNNN` id and no `level` key (e.g.
    t-1608) -- they lack the id-scheme signal, and treating them as node
    markers would risk silently absorbing an unrelated task's identity into
    a node role on a much weaker signal (a possibly-stale `type` value
    alone)."""
    return task.get("id", "").startswith(NODE_ID_PREFIX) and bool(task.get("epic"))


def collect_epic_slugs(tasks):
    """Return the sorted set of unique non-empty flat `epic` string values."""
    return sorted({t["epic"] for t in tasks if t.get("epic")})


def find_existing_epic_nodes(tasks):
    """slug -> node task id, for tasks matching is_epic_node_marker. First
    match wins if more than one task claims a slug (not observed in live
    data -- each slug has at most one `in-` marker)."""
    nodes = {}
    for t in tasks:
        if is_epic_node_marker(t):
            nodes.setdefault(t["epic"], t["id"])
    return nodes


def make_epic_node(node_id, slug, today):
    """Build a new epic-node task dict. Field shape mirrors cmd_add's
    defaults for a freshly-created task (backlog.rs:695-705: status=pending,
    execution=code, tags=[], blocked_by=[], priority=P3, ac_state=none) for
    consistency with normally-added tasks -- excluding the deprecated
    `strategy`/`build_step` fields cmd_add still null-pads (those were
    already dropped repo-wide by drop-deprecated-fields.py; reintroducing
    them on new tasks would be a regression)."""
    return {
        "id": node_id,
        "subject": slug,
        "type": "epic",
        "status": "pending",
        "execution": "code",
        "created": today,
        "tags": [],
        "blocked_by": [],
        "priority": "P3",
        "ac_state": "none",
        "parent": None,
    }


def plan_epic_nodes(tasks, next_id_fn, today):
    """Compute the full node plan: for each unique epic slug, reuse an
    existing marker node (is_epic_node_marker) or allocate a new epic-type
    task via next_id_fn(tasks_so_far). Does not mutate `tasks`.

    Returns (node_id_by_slug, new_node_tasks, reused_slugs, created_slugs).
    next_id_fn is called once per new node against a growing working list so
    ids never collide within a single run (mirrors next_id()'s
    max-numeric-suffix scheme)."""
    existing = find_existing_epic_nodes(tasks)
    slugs = collect_epic_slugs(tasks)
    node_id_by_slug = {}
    new_nodes = []
    reused = []
    created = []
    working = list(tasks)
    for slug in slugs:
        if slug in existing:
            node_id_by_slug[slug] = existing[slug]
            reused.append(slug)
            continue
        new_node_id = next_id_fn(working)
        node = make_epic_node(new_node_id, slug, today)
        working.append(node)
        new_nodes.append(node)
        node_id_by_slug[slug] = new_node_id
        created.append(slug)
    return node_id_by_slug, new_nodes, reused, created


def retype_reused_nodes(tasks, reused_node_ids):
    """For each task id in reused_node_ids (existing `initiative`-type
    markers being repurposed as epic nodes), set type="epic" if not already.
    Idempotent. Returns count changed.

    This completes ADR-065's "remove the initiative node level entirely" /
    "epic is the sole top node" for the 4 pre-existing markers -- leaving
    them at type="initiative" after this script runs would contradict the
    ADR this script implements. Judgment call: the ISC did not spell this
    out explicitly for REUSED nodes (only for newly-created ones); flagged
    in the report for visibility, reversible via git."""
    changed = 0
    id_set = set(reused_node_ids)
    for t in tasks:
        if t.get("id") in id_set and t.get("type") != "epic":
            t["type"] = "epic"
            changed += 1
    return changed


def reparent_by_epic(tasks, node_id_by_slug):
    """Set parent = node_id_by_slug[task.epic] on every task that (a) has a
    non-empty epic field, (b) is NOT itself the node for that slug, and (c)
    has no pre-existing parent. See the module docstring
    "Why parented tasks are not re-parented" -- tasks that already sit under
    a milestone/phase keep that parent; only previously-flat (parentless)
    tasks are pulled under the new epic node. Returns the count reparented."""
    count = 0
    for t in tasks:
        slug = t.get("epic")
        if not slug:
            continue
        node_id = node_id_by_slug.get(slug)
        if node_id is None or t.get("id") == node_id:
            continue
        if t.get("parent"):
            continue
        t["parent"] = node_id
        count += 1
    return count


def drop_epic_keys(tasks):
    """Delete the `epic` key from every task (including node tasks, per the
    ISC step 5). Returns the count of keys dropped."""
    count = 0
    for t in tasks:
        if "epic" in t:
            del t["epic"]
            count += 1
    return count


def migrate(tasks, next_id_fn=next_id, today=None):
    """Run the full Transform 1 + Transform 2 pipeline in place over `tasks`
    (mutates the list -- including appending new epic-node tasks -- and
    returns a report dict of the counts described in the CLI's dry-run
    output). Pure aside from the in-place mutation and `today`'s default
    (real wall-clock date, injectable for deterministic tests). Safe to call
    twice for idempotency: after a first call every `level`/`epic` key is
    gone, so a second call reports all-zero counts."""
    if today is None:
        today = datetime.date.today().isoformat()

    level_backfilled = 0
    level_dropped = 0
    for t in tasks:
        backfilled, had_level = collapse_level(t)
        if backfilled:
            level_backfilled += 1
        if had_level:
            level_dropped += 1

    node_id_by_slug, new_nodes, reused_slugs, created_slugs = plan_epic_nodes(
        tasks, next_id_fn, today
    )
    tasks.extend(new_nodes)

    reused_ids = [node_id_by_slug[s] for s in reused_slugs]
    epic_nodes_retyped = retype_reused_nodes(tasks, reused_ids)

    tasks_reparented = reparent_by_epic(tasks, node_id_by_slug)
    epic_keys_dropped = drop_epic_keys(tasks)

    return {
        "level_backfilled": level_backfilled,
        "level_dropped": level_dropped,
        "epic_slugs_found": len(node_id_by_slug),
        "epic_nodes_created": len(created_slugs),
        "epic_nodes_reused": len(reused_slugs),
        "epic_nodes_retyped": epic_nodes_retyped,
        "tasks_reparented": tasks_reparented,
        "epic_keys_dropped": epic_keys_dropped,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--write", action="store_true", help="actually apply the migration (default: dry-run report only)")
    args = parser.parse_args()

    path = find_tasks_file()
    if not path.exists():
        print(f"tasks.json not found at {path}")
        return

    if args.write and is_tasks_file_dirty(path):
        print(
            f"refusing to write: {path} has uncommitted changes "
            "(git status --porcelain). Commit or stash first, then rerun with --write.",
            file=sys.stderr,
        )
        sys.exit(1)

    raw = json.loads(path.read_text())
    tasks = raw.get("tasks", raw) if isinstance(raw, dict) else raw

    report = migrate(tasks)

    print(f"{path}:")
    print(f"  level backfilled (level -> type): {report['level_backfilled']}")
    print(f"  level keys dropped: {report['level_dropped']}")
    print(f"  unique epic slugs found: {report['epic_slugs_found']}")
    print(
        f"  epic-node tasks created: {report['epic_nodes_created']} "
        f"(reused existing marker: {report['epic_nodes_reused']})"
    )
    print(f"  epic-node types normalized initiative -> epic: {report['epic_nodes_retyped']}")
    print(f"  tasks re-parented to an epic node: {report['tasks_reparented']}")
    print(f"  epic keys dropped: {report['epic_keys_dropped']}")

    any_change = any(v > 0 for v in report.values())
    if not any_change:
        print("\nNo changes needed -- already migrated.")
        return

    if not args.write:
        print("\nDry-run only -- rerun with --write to apply.")
        return

    if isinstance(raw, dict):
        raw["tasks"] = tasks
    else:
        raw = tasks
    tmp_path = path.with_suffix(path.suffix + f".tmp.{os.getpid()}")
    tmp_path.write_text(json.dumps(raw, indent=2, ensure_ascii=False) + "\n")
    tmp_path.replace(path)
    print("\nWritten.")


if __name__ == "__main__":
    main()
