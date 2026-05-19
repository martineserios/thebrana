#!/usr/bin/env python3
"""Remap stream values from old 11-value taxonomy to new 3-value taxonomy.
Idempotent — already-mapped values are left unchanged."""

import json
import pathlib

HOME = pathlib.Path.home()
ENTER = HOME / "enter_thebrana"

REMAP = {
    "roadmap":      "dev",
    "architecture": "dev",
    "bugs":         "dev",
    "tech-debt":    "dev",
    "dx":           "dev",
    "maintenance":  "ops",
    "docs":         "ops",
    "research":     "research",
    "experiments":  "research",
    "knowledge":    "research",
}
VALID = {"dev", "ops", "research"}

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

total_remapped = 0

for rel in BACKLOG_PATHS:
    path = ENTER / rel
    if not path.exists():
        continue
    raw = json.loads(path.read_text())
    tasks = raw.get("tasks", raw) if isinstance(raw, dict) else raw
    if not tasks:
        continue

    remapped = 0
    for t in tasks:
        stream = t.get("stream")
        if stream in VALID:
            continue
        if stream in REMAP:
            t["stream"] = REMAP[stream]
            remapped += 1
        elif stream is None:
            t["stream"] = "dev"
            remapped += 1
        # "personal" stream left as-is (extract-personal.py handles removal)

    if remapped:
        if isinstance(raw, dict):
            raw["tasks"] = tasks
        else:
            raw = tasks
        path.write_text(json.dumps(raw, indent=2, ensure_ascii=False))
        print(f"  {rel}: {remapped} tasks remapped")
    total_remapped += remapped

print(f"\nTotal: {total_remapped} tasks remapped")
