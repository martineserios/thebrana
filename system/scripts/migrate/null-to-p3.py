#!/usr/bin/env python3
"""Set priority=P3 on all pending tasks where priority is null.
Idempotent — completed/cancelled tasks are skipped."""

import json
import pathlib

HOME = pathlib.Path.home()
ENTER = HOME / "enter_thebrana"

BACKLOG_PATHS = [
    "thebrana/.claude/tasks.json",
    "personal/.claude/tasks.json",
    "ventures/proyecto_anita/.claude/tasks.json",
    "ventures/nexeye_eyedetect/.claude/tasks.json",
    "clients/somos_mirada/.claude/tasks.json",
    "ventures/psilea/.claude/tasks.json",
    "ventures/lexia/.claude/tasks.json",
    "ventures/tinyhomes/.claude/tasks.json",
    "clients/unlock/.claude/tasks.json",
    "ventures/brapsoclaw/.claude/tasks.json",
    "ventures/ai-native-education/.claude/tasks.json",
    "clients/batrade/.claude/tasks.json",
    "clients/prof_man/.claude/tasks.json",
    "ventures/proyecto_anita/clients/mya/.claude/tasks.json",
    "ventures/linkedin/.claude/tasks.json",
    "clients/crea/.claude/tasks.json",
]

total_updated = 0

for rel in BACKLOG_PATHS:
    path = ENTER / rel
    if not path.exists():
        continue
    raw = json.loads(path.read_text())
    tasks = raw.get("tasks", raw) if isinstance(raw, dict) else raw
    if not tasks:
        continue

    updated = 0
    for t in tasks:
        if t.get("priority") is None and t.get("status") == "pending":
            t["priority"] = "P3"
            updated += 1

    if updated:
        if isinstance(raw, dict):
            raw["tasks"] = tasks
        else:
            raw = tasks
        path.write_text(json.dumps(raw, indent=2, ensure_ascii=False))
        print(f"  {rel}: {updated} tasks → P3")
    total_updated += updated

print(f"\nTotal: {total_updated} tasks updated to P3")
