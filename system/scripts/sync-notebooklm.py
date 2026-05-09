#!/usr/bin/env python3
"""
sync-notebooklm.py — Sync brana-knowledge dimension docs to NotebookLM staging.

Tracks which docs have been synced via a hash-based state file. On each run:
  - New docs (in dims dir, not in state) → staged for upload
  - Changed docs (hash differs) → re-staged for update
  - Removed docs (in state, not in dims dir) → flagged for manual deletion
  - Unchanged docs → skipped

NotebookLM has no public API; staged files require manual upload in the browser.
Run this script, then follow the printed action list.

Usage:
    uv run python sync-notebooklm.py [options]

Options:
    --dims-dir PATH     Dimension docs directory (default: brana-knowledge/dimensions)
    --state-file PATH   JSON state file path (default: brana-knowledge/.notebooklm-sync.json)
    --output-dir PATH   Staging output directory (default: /tmp/notebooklm-sync)
    --dry-run           Show what would happen without writing files
    --help              Show this message
"""

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_DIMS = Path.home() / "enter_thebrana" / "brana-knowledge" / "dimensions"
DEFAULT_STATE = Path.home() / "enter_thebrana" / "brana-knowledge" / ".notebooklm-sync.json"
DEFAULT_OUTPUT = Path("/tmp/notebooklm-sync")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def prepare_doc(content: str) -> str:
    """Light cleanup: replace relative markdown links with plain text."""
    # [link text](./path.md) → link text
    content = re.sub(r'\[([^\]]+)\]\([^)]+\.md[^)]*\)', r'\1', content)
    # Remove image refs: ![alt](path)
    content = re.sub(r'!\[[^\]]*\]\([^)]*\)', '', content)
    # Collapse triple+ blank lines
    content = re.sub(r'\n{4,}', '\n\n\n', content)
    return content.strip() + '\n'


def load_state(state_file: Path) -> dict:
    if state_file.exists():
        try:
            return json.loads(state_file.read_text())
        except (json.JSONDecodeError, OSError):
            return {}
    return {}


def save_state(state_file: Path, state: dict) -> None:
    state_file.parent.mkdir(parents=True, exist_ok=True)
    state_file.write_text(json.dumps(state, indent=2, sort_keys=True) + '\n')


def scan_dims(dims_dir: Path) -> dict[str, Path]:
    """Return {filename: path} for all non-hidden .md files in dims_dir."""
    result = {}
    for p in sorted(dims_dir.glob("*.md")):
        if not p.name.startswith('.'):
            result[p.name] = p
    return result


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Sync dimension docs to NotebookLM staging directory.",
        add_help=True,
    )
    parser.add_argument("--dims-dir", type=Path, default=DEFAULT_DIMS)
    parser.add_argument("--state-file", type=Path, default=DEFAULT_STATE)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--dry-run", action="store_true",
                        help="Show actions without writing files")
    args = parser.parse_args()

    dims_dir: Path = args.dims_dir
    state_file: Path = args.state_file
    output_dir: Path = args.output_dir
    dry_run: bool = args.dry_run

    if not dims_dir.is_dir():
        print(f"ERROR: dims-dir not found: {dims_dir}", file=sys.stderr)
        return 1

    docs = scan_dims(dims_dir)
    state = load_state(state_file)

    to_add = []
    to_update = []
    to_delete = []
    skipped = 0

    # Check each doc against state
    for name, path in docs.items():
        current_hash = sha256_file(path)
        if name not in state:
            to_add.append((name, path, current_hash))
        elif state[name]["hash"] != current_hash:
            to_update.append((name, path, current_hash))
        else:
            skipped += 1

    # Check for removed docs
    for name in list(state.keys()):
        if name not in docs:
            to_delete.append(name)

    # Print summary
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    dry_tag = " [DRY RUN]" if dry_run else ""
    print(f"NotebookLM Sync — {now}{dry_tag}")
    print(f"Dims: {dims_dir}  |  State: {state_file}  |  Output: {output_dir}")
    print()

    if not to_add and not to_update and not to_delete:
        print(f"✓ Nothing to do. All {skipped} doc(s) up to date.")
        return 0

    if to_add:
        print(f"ADD ({len(to_add)} new doc(s)) — upload these in NotebookLM → Add source → Upload file:")
        for name, _, _ in to_add:
            print(f"  + {output_dir}/{name}")
        print()

    if to_update:
        print(f"UPDATE ({len(to_update)} changed doc(s)) — re-upload these in NotebookLM:")
        for name, _, _ in to_update:
            print(f"  ~ {output_dir}/{name}")
        print()

    if to_delete:
        print(f"DELETE ({len(to_delete)} removed doc(s)) — manually delete these sources in NotebookLM:")
        for name in to_delete:
            print(f"  - {name}")
        print()

    if skipped:
        print(f"  (skipped {skipped} unchanged doc(s))")
        print()

    if dry_run:
        print("Dry run — no files written.")
        return 0

    # Stage files and update state
    output_dir.mkdir(parents=True, exist_ok=True)

    for name, path, current_hash in to_add + to_update:
        content = prepare_doc(path.read_text(encoding="utf-8", errors="replace"))
        (output_dir / name).write_text(content, encoding="utf-8")
        state[name] = {"hash": current_hash, "synced_at": now}

    for name in to_delete:
        del state[name]

    save_state(state_file, state)
    print(f"Done. Staged {len(to_add) + len(to_update)} file(s) in {output_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
