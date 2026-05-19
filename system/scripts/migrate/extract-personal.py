#!/usr/bin/env python3
"""Extract tasks with stream=personal from thebrana/.claude/tasks.json
into personal/.claude/tasks.json. Idempotent — safe to re-run."""

import json
import pathlib
import sys

HOME = pathlib.Path.home()
ENTER = HOME / "enter_thebrana"
SOURCE = ENTER / "thebrana" / ".claude" / "tasks.json"
TARGET = ENTER / "personal" / ".claude" / "tasks.json"


def load(path: pathlib.Path):
    raw = json.loads(path.read_text())
    return raw.get("tasks", raw) if isinstance(raw, dict) else raw, isinstance(raw, dict)


def save(path: pathlib.Path, tasks, is_wrapped: bool):
    path.parent.mkdir(parents=True, exist_ok=True)
    if is_wrapped:
        existing = json.loads(path.read_text()) if path.exists() else {}
        existing["tasks"] = tasks
        path.write_text(json.dumps(existing, indent=2, ensure_ascii=False))
    else:
        path.write_text(json.dumps(tasks, indent=2, ensure_ascii=False))


source_tasks, source_wrapped = load(SOURCE)

personal_tasks = [t for t in source_tasks if t.get("stream") == "personal"]
remaining = [t for t in source_tasks if t.get("stream") != "personal"]

if not personal_tasks:
    print("No personal tasks found — nothing to extract.")
    sys.exit(0)

# Load existing personal tasks and merge (skip duplicates by id)
if TARGET.exists():
    existing_personal, tgt_wrapped = load(TARGET)
    existing_ids = {t.get("id") for t in existing_personal}
    new_personal = [t for t in personal_tasks if t.get("id") not in existing_ids]
    merged_personal = existing_personal + new_personal
    print(f"  personal/.claude/tasks.json: +{len(new_personal)} new, {len(existing_personal)} existing")
else:
    merged_personal = personal_tasks
    tgt_wrapped = True
    print(f"  personal/.claude/tasks.json: creating with {len(merged_personal)} tasks")

save(TARGET, merged_personal, tgt_wrapped)

# Save thebrana without personal tasks
if SOURCE.exists():
    raw = json.loads(SOURCE.read_text())
    if isinstance(raw, dict):
        raw["tasks"] = remaining
    else:
        raw = remaining
    SOURCE.write_text(json.dumps(raw, indent=2, ensure_ascii=False))

print(f"  thebrana: removed {len(personal_tasks)} personal tasks, {len(remaining)} remain")
