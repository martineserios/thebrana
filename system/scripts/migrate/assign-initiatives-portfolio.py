#!/usr/bin/env python3
"""Assign one initiative slug per project to all pending/in_progress tasks.
Idempotent: only sets initiative where it is currently null.
Skips completed/cancelled tasks — no value in tagging historical work.
Initiative slugs reflect current active focus as of 2026-05-20."""

import json
import pathlib

HOME = pathlib.Path.home()
ENTER = HOME / "enter_thebrana"

# (backlog_path, initiative_slug, basis)
PROJECT_INITIATIVES = [
    ("personal/.claude/tasks.json",                                   "life-os",               "active personal system work"),
    ("ventures/proyecto_anita/.claude/tasks.json",                    "delorenzi-onboarding",  "first official client, target 2026-06-01"),
    ("ventures/nexeye_eyedetect/.claude/tasks.json",                  "vercel-migration",      "active Vercel migration effort"),
    ("clients/somos_mirada/.claude/tasks.json",                       "meta-hygiene",          "meta-account-hygiene proposal active"),
    ("ventures/lexia/.claude/tasks.json",                             "template-delivery",     "blocked on Trusso templates"),
    ("clients/batrade/.claude/tasks.json",                            "phase-1-visibility",    "phase 1: visibility + order"),
    ("clients/unlock/.claude/tasks.json",                             "initial-build",         "starting 2026-05-13"),
    ("ventures/brapsoclaw/.claude/tasks.json",                        "whatsapp-bot",          "NanoClaw fork on Kapso"),
    ("ventures/ai-native-education/.claude/tasks.json",               "pilot-launch",          "Clase 1 launched 2026-04-30"),
    ("ventures/tinyhomes/.claude/tasks.json",                         "cofounder-unblock",     "blocked on cofounder"),
    ("ventures/linkedin/.claude/tasks.json",                          "phase-a-validation",    "30-day manual validation phase"),
    ("ventures/proyecto_anita/clients/mya/.claude/tasks.json",        "pilot-prep",            "waiting on proposal response"),
    ("clients/prof_man/.claude/tasks.json",                           "indicator-build",       "TradingView indicators for client"),
    ("ventures/proyecto_anita/clients/las_lupes/.claude/tasks.json",  "proposal-response",     "waiting on Charlie"),
    ("clients/las_lupes/.claude/tasks.json",                          "proposal-response",     "waiting on Charlie"),
]

ACTIVE_STATUSES = {"pending", "in_progress", None, ""}

total_tagged = 0

for rel, slug, basis in PROJECT_INITIATIVES:
    path = ENTER / rel
    if not path.exists():
        continue

    raw = json.loads(path.read_text())
    tasks = raw.get("tasks", raw) if isinstance(raw, dict) else raw
    if not tasks:
        continue

    tagged = 0
    for t in tasks:
        st = t.get("status") or ""
        if st in ("completed", "cancelled"):
            continue
        if t.get("initiative") is not None:
            continue
        t["initiative"] = slug
        tagged += 1

    if tagged:
        if isinstance(raw, dict):
            raw["tasks"] = tasks
        else:
            raw = tasks
        path.write_text(json.dumps(raw, indent=2, ensure_ascii=False))

    print(f"  {rel.split('/')[-3] if '/' in rel else rel}: {tagged} tagged → {slug}  ({basis})")
    total_tagged += tagged

print(f"\nPortfolio total: {total_tagged} tasks tagged across {len(PROJECT_INITIATIVES)} projects")
