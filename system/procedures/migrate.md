# Procedure: Backlog Migrations

Run migration scripts when a schema change requires bulk updates across multiple tasks.json files.

## When to write a migration

- New optional field added to the task schema
- Field renamed or removed (deprecation)
- Enum vocabulary collapsed or expanded (e.g. stream 11→3)
- Bulk assignment of a new classification (e.g. initiative, work_type backfill)
- Moving tasks between backlogs (e.g. personal task extraction)

Do NOT write a migration for:
- Single-task field updates (use `brana backlog set <id> <field> <value>`)
- One-project changes (edit tasks.json directly or use `brana backlog set`)

## Script template

```python
#!/usr/bin/env python3
"""One-line description of what this migration does."""

import json
import pathlib

HOME = pathlib.Path.home()
ENTER = HOME / "enter_thebrana"

BACKLOG_PATHS = [
    "thebrana/.claude/tasks.json",
    "personal/.claude/tasks.json",
    "ventures/proyecto_anita/.claude/tasks.json",
    # ... all active project paths
]

total_changed = 0

for rel in BACKLOG_PATHS:
    path = ENTER / rel
    if not path.exists():
        continue
    raw = json.loads(path.read_text())
    tasks = raw.get("tasks", raw) if isinstance(raw, dict) else raw
    if not tasks:
        continue

    changed = 0
    for t in tasks:
        # IDEMPOTENCY: skip tasks that already have the correct state
        if t.get("new_field") is not None:
            continue
        # --- mutation logic ---
        t["new_field"] = compute_value(t)
        changed += 1

    if changed:
        if isinstance(raw, dict):
            raw["tasks"] = tasks
        else:
            raw = tasks
        path.write_text(json.dumps(raw, indent=2, ensure_ascii=False))

    print(f"  {rel}: {changed} updated")
    total_changed += changed

print(f"\nTotal: {total_changed} updated")
```

Key rules:
- **Idempotent**: guard `if t.get("field") is not None: continue` before every mutation
- **Skip inactive statuses** when appropriate: `if t.get("status") in ("completed", "cancelled"): continue`
- **Write-back**: always write the outer `raw` dict back (not just `tasks`) to preserve schema envelope
- **Report**: print per-file counts + grand total

## Naming convention

`{verb}-{noun}.py` — alphabetical order = safe topological order for dependent scripts.

Examples: `assign-initiatives-portfolio.py`, `drop-deprecated-fields.py`, `infer-work-type.py`

## Run order and dependencies

The 5 existing scripts have this dependency order:

```
extract-personal.py        (no deps — run first if personal tasks exist in thebrana)
    ↓
null-to-p3.py              (no deps)
remap-streams.py           (no deps)
drop-deprecated-fields.py  (no deps, but run after remap-streams so stream is clean)
    ↓
infer-work-type.py         (depends on stream being correct — run after remap-streams)
```

New migrations for initiative assignment:
```
assign-initiatives-thebrana.py   (depends on thebrana tasks.json being migrated)
assign-initiatives-portfolio.py  (independent of thebrana)
```

## Adding a new project to BACKLOG_PATHS

When a new project is created, add its path to BACKLOG_PATHS in every existing migration script
that should cover it. Then re-run those scripts — idempotency means re-runs are safe.

## Verification after running

```bash
# 1. Count null work_types across portfolio
python3 -c "
import json, pathlib
ENTER = pathlib.Path.home() / 'enter_thebrana'
paths = [
    'thebrana/.claude/tasks.json', 'personal/.claude/tasks.json',
    'ventures/proyecto_anita/.claude/tasks.json', 'ventures/nexeye_eyedetect/.claude/tasks.json',
    'clients/somos_mirada/.claude/tasks.json', 'ventures/lexia/.claude/tasks.json',
    'ventures/tinyhomes/.claude/tasks.json', 'clients/unlock/.claude/tasks.json',
    'ventures/brapsoclaw/.claude/tasks.json', 'ventures/ai-native-education/.claude/tasks.json',
    'clients/batrade/.claude/tasks.json', 'clients/prof_man/.claude/tasks.json',
    'ventures/proyecto_anita/clients/mya/.claude/tasks.json',
    'ventures/linkedin/.claude/tasks.json', 'clients/crea/.claude/tasks.json',
]
for rel in paths:
    p = ENTER / rel
    if not p.exists(): continue
    raw = json.loads(p.read_text())
    tasks = raw.get('tasks', raw) if isinstance(raw, dict) else raw
    n = sum(1 for t in tasks if not t.get('work_type'))
    if n: print(f'FAIL {rel}: {n} null work_type')
print('OK: work_type coverage complete')
"

# 2. Spot-check an initiative query
brana backlog query --initiative backlog-ui 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d), 'tasks')"

# 3. Verify active initiative + focus output
brana backlog focus

# 4. Run test suite
cd system/cli/rust && cargo test 2>&1 | tail -3
```

## Worked examples

| Script | What it does |
|--------|-------------|
| `extract-personal.py` | Moves `stream=personal` tasks from thebrana to personal/.claude/tasks.json |
| `null-to-p3.py` | Sets `priority=P3` for pending tasks where priority is null |
| `remap-streams.py` | Collapses 11-value stream taxonomy to 3 (dev/ops/research) |
| `drop-deprecated-fields.py` | Removes build_step, strategy, execution; infers work_type=ops from execution=manual |
| `infer-work-type.py` | Fills null work_type via subject patterns → stream fallback → implement catch-all |
| `assign-initiatives-thebrana.py` | Tags thebrana current-work clusters with initiative slugs (explicit IDs only) |
| `assign-initiatives-portfolio.py` | Tags all pending/in_progress tasks per project with one initiative slug |
