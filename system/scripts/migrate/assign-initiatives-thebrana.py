#!/usr/bin/env python3
"""Assign initiative slugs to thebrana tasks by explicit ID mapping.
Idempotent: only sets initiative where it is currently null.
Uses explicit IDs (not tag-based matching) to avoid over-tagging historical work.
Initiative marks CURRENT active clusters, not all historical work on a topic."""

import json
import pathlib

HOME = pathlib.Path.home()
ENTER = HOME / "enter_thebrana"
BACKLOG = ENTER / "thebrana/.claude/tasks.json"

# Web UI phase: t-1501 through t-1526
WEB_UI_IDS = {f"t-{n}": "backlog-ui" for n in range(1501, 1527)}

# Focused current-work clusters — explicit IDs only
EXPLICIT: dict[str, str] = {
    # memory-arch: memory architecture redesign tasks
    "t-1491": "memory-arch",
    "t-1492": "memory-arch",
    "t-1497": "memory-arch",
    "t-1498": "memory-arch",
    # rust-cli: current Rust CLI quality tasks
    "t-1530": "rust-cli",
    "t-1532": "rust-cli",
    "t-1533": "rust-cli",
    # cc-alignment: already tagged — not listed here, never overwrite
}

ALL_ASSIGNMENTS = {**WEB_UI_IDS, **EXPLICIT}

raw = json.loads(BACKLOG.read_text())
tasks = raw.get("tasks", raw) if isinstance(raw, dict) else raw

counts: dict[str, int] = {}
skipped = 0

for t in tasks:
    if t.get("initiative") is not None:
        skipped += 1
        continue
    tid = t.get("id", "")
    initiative = ALL_ASSIGNMENTS.get(tid)
    if initiative:
        t["initiative"] = initiative
        counts[initiative] = counts.get(initiative, 0) + 1

if isinstance(raw, dict):
    raw["tasks"] = tasks
else:
    raw = tasks
BACKLOG.write_text(json.dumps(raw, indent=2, ensure_ascii=False))

print("thebrana initiative assignment:")
for slug, n in sorted(counts.items()):
    print(f"  {slug}: {n} tasks tagged")
print(f"  (skipped {skipped} already-tagged tasks)")
print(f"  total tagged this run: {sum(counts.values())}")
