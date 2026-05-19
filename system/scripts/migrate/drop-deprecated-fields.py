#!/usr/bin/env python3
"""Remove deprecated fields (build_step, strategy, execution) from all tasks.
Before dropping execution, infer work_type=ops for manual-execution tasks."""

import json
import pathlib

HOME = pathlib.Path.home()
ENTER = HOME / "enter_thebrana"

DEPRECATED = ["build_step", "strategy", "execution"]

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

total_dropped = 0
total_inferred = 0

for rel in BACKLOG_PATHS:
    path = ENTER / rel
    if not path.exists():
        continue
    raw = json.loads(path.read_text())
    tasks = raw.get("tasks", raw) if isinstance(raw, dict) else raw
    if not tasks:
        continue

    dropped = 0
    inferred = 0
    for t in tasks:
        # Infer work_type from execution before dropping
        if t.get("execution") == "manual" and t.get("work_type") is None:
            t["work_type"] = "ops"
            inferred += 1

        for field in DEPRECATED:
            if field in t:
                del t[field]
                dropped += 1

    if dropped or inferred:
        if isinstance(raw, dict):
            raw["tasks"] = tasks
        else:
            raw = tasks
        path.write_text(json.dumps(raw, indent=2, ensure_ascii=False))
        print(f"  {rel}: {dropped} fields removed, {inferred} work_type inferred from execution")
    total_dropped += dropped
    total_inferred += inferred

print(f"\nTotal: {total_dropped} deprecated fields removed, {total_inferred} work_types inferred")
