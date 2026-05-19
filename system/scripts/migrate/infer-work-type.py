#!/usr/bin/env python3
"""Infer work_type from subject patterns and stream where it's null.
Reports tasks left null for manual triage."""

import json
import pathlib
import re

HOME = pathlib.Path.home()
ENTER = HOME / "enter_thebrana"

IMPLEMENT_RE = re.compile(
    r"\[hook\]|\[feat\]|implement|build|add|refactor|fix|wire|extend|migrate|upgrade|replace|create|write|generate",
    re.IGNORECASE,
)
RESEARCH_RE = re.compile(
    r"research|evaluate|spike|investigate|audit|explore|analyse|analyze|review|compare|assess",
    re.IGNORECASE,
)
OPS_RE = re.compile(
    r"deploy|migrate|config|setup|run|sync|install|backup|monitor|release|publish|schedule|cron|rotate",
    re.IGNORECASE,
)

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

total_inferred = 0
total_null = 0

for rel in BACKLOG_PATHS:
    path = ENTER / rel
    if not path.exists():
        continue
    raw = json.loads(path.read_text())
    tasks = raw.get("tasks", raw) if isinstance(raw, dict) else raw
    if not tasks:
        continue

    inferred = 0
    null_tasks = []
    for t in tasks:
        if t.get("work_type") is not None:
            continue
        subject = t.get("subject", "")
        stream = t.get("stream", "")
        kind = t.get("kind", "") or t.get("type", "")

        wt = None
        if stream == "research" or RESEARCH_RE.search(subject):
            wt = "research"
        elif OPS_RE.search(subject):
            wt = "ops"
        elif IMPLEMENT_RE.search(subject) or kind in ("feature", "bug", "fix", "refactor"):
            wt = "implement"

        if wt:
            t["work_type"] = wt
            inferred += 1
        else:
            null_tasks.append(t.get("id", "?"))

    if inferred:
        if isinstance(raw, dict):
            raw["tasks"] = tasks
        else:
            raw = tasks
        path.write_text(json.dumps(raw, indent=2, ensure_ascii=False))

    print(f"  {rel}: {inferred} inferred, {len(null_tasks)} left null")
    if null_tasks:
        print(f"    null ids: {', '.join(null_tasks[:10])}{'...' if len(null_tasks) > 10 else ''}")
    total_inferred += inferred
    total_null += len(null_tasks)

print(f"\nTotal: {total_inferred} inferred, {total_null} left null (manual triage needed)")
