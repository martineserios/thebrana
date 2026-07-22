#!/usr/bin/env python3
"""Normalize the tags field to array-of-strings in thebrana's tasks.json
(t-2309, ADR-065 backlog v3 schema migration).

tags is documented as an array of strings but has drifted: some tasks store
it as a comma-joined string, some as null. Both silently break `.as_array()`
reads in the Rust CLI -- those tasks are invisibly skipped by tag filters,
tag inventory, and complexity scoring today. This normalizes:
  - comma-joined string -> array (trimmed, empty elements dropped)
  - null -> []
  - already-array -> left untouched

Scoped to thebrana's own tasks.json only (not portfolio-wide) -- this is a
backlog-v3 schema migration for this repo's backlog, not a cross-project
data hygiene sweep.

Usage:
    python3 normalize-tags.py            # dry-run (default): report only
    python3 normalize-tags.py --write    # actually normalize tags in place
"""
import argparse
import json
import os
import pathlib
import subprocess


def find_tasks_file() -> pathlib.Path:
    """Locate this repo's tasks.json via git root, mirroring the Rust CLI's
    find_tasks_file() resolution (walk up from cwd to the nearest git root,
    then .claude/tasks.json)."""
    root = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    return pathlib.Path(root) / ".claude" / "tasks.json"


def normalize_tags(tags):
    """Return (normalized_list, changed) for a single task's tags value.

    Pure function -- no I/O. Already-array values pass through unchanged
    (changed=False) even when empty.
    """
    if isinstance(tags, list):
        return tags, False
    if tags is None:
        return [], True
    if isinstance(tags, str):
        parts = [p.strip() for p in tags.split(",")]
        return [p for p in parts if p], True
    # Unexpected type (number/bool/object) -- not observed in production data;
    # normalize to empty rather than guess at intent.
    return [], True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="actually normalize tags in place (default: dry-run report only)")
    args = parser.parse_args()

    path = find_tasks_file()
    if not path.exists():
        print(f"tasks.json not found at {path}")
        return

    raw = json.loads(path.read_text())
    tasks = raw.get("tasks", raw) if isinstance(raw, dict) else raw

    changed_ids = []
    for t in tasks:
        normalized, was_changed = normalize_tags(t.get("tags"))
        if was_changed:
            t["tags"] = normalized
            changed_ids.append(t.get("id", "?"))

    print(f"{path}: {len(changed_ids)} tasks normalized")
    if changed_ids:
        print(f"  ids: {', '.join(changed_ids)}")

    if changed_ids and args.write:
        if isinstance(raw, dict):
            raw["tasks"] = tasks
        else:
            raw = tasks
        tmp_path = path.with_suffix(path.suffix + f".tmp.{os.getpid()}")
        tmp_path.write_text(json.dumps(raw, indent=2, ensure_ascii=False) + "\n")
        tmp_path.replace(path)
        print("  written.")
    elif changed_ids:
        print("\nDry-run only -- rerun with --write to apply.")


if __name__ == "__main__":
    main()
