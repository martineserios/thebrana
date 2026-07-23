#!/usr/bin/env python3
"""Drop the retired flat `stream` field from thebrana's tasks.json (t-2325,
ADR-065 backlog v3 schema cleanup).

ADR-065 retired `stream` (dev/ops/research) alongside level/epic/initiative --
superseded by tags/epic. t-2312's collapse-level-epic-v3.py never touched it
(only level/epic were in scope for that migration); this script closes that
gap with the same mechanics: dry-run by default, git-dirty guard before
--write, scoped to thebrana's own tasks.json (not portfolio-wide, matching
t-2309's normalize-tags.py / t-2312's collapse-level-epic-v3.py precedent).

Usage:
    python3 drop-stream-field-v3.py            # dry-run (default): report only
    python3 drop-stream-field-v3.py --write     # actually apply + write
"""
import argparse
import json
import os
import pathlib
import subprocess
import sys


def find_tasks_file() -> pathlib.Path:
    """Locate this repo's tasks.json via git root (mirrors brana-core's
    find_tasks_file() resolution -- same approach as collapse-level-epic-v3.py)."""
    root = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    return pathlib.Path(root) / ".claude" / "tasks.json"


def is_tasks_file_dirty(tasks_path: pathlib.Path) -> bool:
    """True if `git status --porcelain` reports uncommitted changes to
    tasks_path specifically. Dry-run never writes, so this is only
    consulted before --write."""
    result = subprocess.run(
        ["git", "status", "--porcelain", "--", str(tasks_path)],
        cwd=tasks_path.parent,
        capture_output=True, text=True, check=True,
    )
    return bool(result.stdout.strip())


def drop_stream_keys(tasks):
    """Delete the `stream` key from every task that carries one. Mutates the
    list in place. Returns the count of keys dropped. Idempotent -- a second
    call over already-migrated tasks reports 0."""
    count = 0
    for t in tasks:
        if "stream" in t:
            del t["stream"]
            count += 1
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--write", action="store_true", help="actually apply the migration (default: dry-run report only)")
    args = parser.parse_args()

    path = find_tasks_file()
    if not path.exists():
        print(f"tasks.json not found at {path}")
        return

    if args.write and is_tasks_file_dirty(path):
        print(
            f"refusing to write: {path} has uncommitted changes "
            "(git status --porcelain). Commit or stash first, then rerun with --write.",
            file=sys.stderr,
        )
        sys.exit(1)

    raw = json.loads(path.read_text())
    tasks = raw.get("tasks", raw) if isinstance(raw, dict) else raw

    dropped = drop_stream_keys(tasks)

    print(f"{path}:")
    print(f"  stream keys dropped: {dropped}")

    if dropped == 0:
        print("\nNo changes needed -- already migrated.")
        return

    if not args.write:
        print("\nDry-run only -- rerun with --write to apply.")
        return

    if isinstance(raw, dict):
        raw["tasks"] = tasks
    else:
        raw = tasks
    tmp_path = path.with_suffix(path.suffix + f".tmp.{os.getpid()}")
    tmp_path.write_text(json.dumps(raw, indent=2, ensure_ascii=False) + "\n")
    tmp_path.replace(path)
    print("\nWritten.")


if __name__ == "__main__":
    main()
