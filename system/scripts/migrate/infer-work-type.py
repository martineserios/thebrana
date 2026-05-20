#!/usr/bin/env python3
"""Infer work_type from subject patterns and stream where it's null.
Applies: pattern matching → stream fallback → implement catch-all (0 nulls target)."""

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
    r"research|evaluate|spike|investigate|audit|explore|analyse|analyze|review|compare|assess"
    r"|deep.?dive|study|learn|reading",
    re.IGNORECASE,
)
DESIGN_RE = re.compile(
    r"\bADR[-\s]?\d+|decision|architect|design|schema|model|ontology|wireframe|\bspec\b",
    re.IGNORECASE,
)
OPS_RE = re.compile(
    r"deploy|config|setup|run|sync|install|backup|monitor|release|publish|schedule|cron|rotate"
    r"|document|update dim|bump|prune|merge branch|commit domain|tag release",
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
    "clients/mandawa/.claude/tasks.json",
    "ventures/prediktive-prep/.claude/tasks.json",
    "ventures/proyecto_anita/clients/las_lupes/.claude/tasks.json",
    "clients/las_lupes/.claude/tasks.json",
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
        elif DESIGN_RE.search(subject):
            wt = "design"
        elif OPS_RE.search(subject):
            wt = "ops"
        elif IMPLEMENT_RE.search(subject) or kind in ("feature", "bug", "fix", "refactor"):
            wt = "implement"
        # stream-based fallback
        elif stream in ("dev", "ops", "research"):
            wt = {"dev": "implement", "ops": "ops", "research": "research"}[stream]
        else:
            # catch-all: any remaining task is work to be done
            wt = "implement"

        t["work_type"] = wt
        inferred += 1

    if inferred:
        if isinstance(raw, dict):
            raw["tasks"] = tasks
        else:
            raw = tasks
        path.write_text(json.dumps(raw, indent=2, ensure_ascii=False))

    print(f"  {rel}: {inferred} inferred")
    total_inferred += inferred

print(f"\nTotal: {total_inferred} inferred, 0 left null")
