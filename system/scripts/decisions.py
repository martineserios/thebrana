#!/usr/bin/env python3
"""Git-tracked, append-only JSONL decision log.

State directory: system/state/decisions/

Usage:
    decisions.py log <agent> <type> <content> [--severity SEV] [--refs r1,r2] [--target T]
    decisions.py read [--last N] [--type TYPE] [--agent NAME] [--severity SEV] [--json]
    decisions.py archive [--days N] [--dry-run]
"""

import argparse
import datetime
import json
import os
import random
import shutil
import sys
from pathlib import Path

VALID_TYPES = {"decision", "finding", "concern", "action", "error", "cost"}


def _find_repo_root(start: Path) -> Path:
    """Walk up from start to find the directory containing .git."""
    current = start.resolve()
    while current != current.parent:
        if (current / ".git").exists():
            return current
        current = current.parent
    raise RuntimeError("Could not find repo root (.git) from " + str(start))


def _state_dir() -> Path:
    """Resolve state dir: BRANA_DECISIONS_DIR env var → repo default."""
    env = os.environ.get("BRANA_DECISIONS_DIR")
    if env:
        return Path(env)
    repo = _find_repo_root(Path(__file__).parent)
    return repo / "system" / "state" / "decisions"


# Module-level state dir — monkeypatched in tests.
STATE_DIR: Path = _state_dir()


def _ensure_dirs() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    (STATE_DIR / "archive").mkdir(exist_ok=True)


def _session_id() -> str:
    env = os.environ.get("BRANA_SESSION_ID")
    if env:
        return env
    now = datetime.datetime.now(datetime.timezone.utc)
    return f"{now.strftime('%H%M%S')}-{os.getpid()}-{random.randint(0, 0xFFFF):04x}"


def _today_str() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")


# ---------------------------------------------------------------------------
# log
# ---------------------------------------------------------------------------

# Cache the session file name so repeated calls in one process reuse it.
_session_file: str | None = None


def log_entry(agent: str, entry_type: str, content: str,
              severity: str | None = None,
              refs: list[str] | None = None,
              target: str | None = None) -> Path:
    """Append one JSON line to today's session file. Returns the file path."""
    global _session_file

    if entry_type not in VALID_TYPES:
        print(f"Error: invalid type '{entry_type}'. Must be one of: {', '.join(sorted(VALID_TYPES))}", file=sys.stderr)
        sys.exit(1)

    _ensure_dirs()

    if _session_file is None:
        _session_file = f"{_today_str()}-{_session_id()}.jsonl"

    entry: dict = {
        "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "agent": agent,
        "type": entry_type,
        "content": content,
    }
    if severity is not None:
        entry["severity"] = severity.upper()
    if refs is not None:
        entry["refs"] = refs
    if target is not None:
        entry["target"] = target

    filepath = STATE_DIR / _session_file
    with open(filepath, "a") as f:
        f.write(json.dumps(entry) + "\n")

    return filepath


# ---------------------------------------------------------------------------
# read
# ---------------------------------------------------------------------------

def read_entries(last: int | None = None,
                 entry_type: str | None = None,
                 agent: str | None = None,
                 severity: str | None = None,
                 as_json: bool = False) -> str:
    """Read and filter JSONL entries. Returns formatted output string."""
    _ensure_dirs()

    entries: list[dict] = []
    for p in sorted(STATE_DIR.glob("*.jsonl")):
        # Skip anything inside archive/
        if p.parent != STATE_DIR:
            continue
        with open(p) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entries.append(json.loads(line))
                except json.JSONDecodeError:
                    continue

    # Sort by timestamp
    entries.sort(key=lambda e: e.get("ts", ""))

    # Apply filters
    if entry_type is not None:
        entries = [e for e in entries if e.get("type") == entry_type]
    if agent is not None:
        entries = [e for e in entries if e.get("agent") == agent]
    if severity is not None:
        entries = [e for e in entries if e.get("severity") == severity.upper()]

    # Last N
    if last is not None and last > 0:
        entries = entries[-last:]

    # Format output
    lines: list[str] = []
    for e in entries:
        if as_json:
            lines.append(json.dumps(e))
        else:
            ts = e.get("ts", "")
            try:
                dt = datetime.datetime.fromisoformat(ts)
                ts_short = dt.strftime("%Y-%m-%d %H:%M")
            except (ValueError, TypeError):
                ts_short = ts[:16]
            sev = e.get("severity")
            prefix = f"[{sev}] " if sev else ""
            lines.append(f"[{ts_short}] {e.get('agent', '?')}/{e.get('type', '?')}: {prefix}{e.get('content', '')}")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# archive
# ---------------------------------------------------------------------------

def archive(days: int = 30, dry_run: bool = False) -> str:
    """Move session files older than *days* to archive/. Returns report."""
    _ensure_dirs()

    cutoff = datetime.datetime.now(datetime.timezone.utc).date() - datetime.timedelta(days=days)
    archive_dir = STATE_DIR / "archive"
    count = 0

    for p in sorted(STATE_DIR.glob("*.jsonl")):
        if p.parent != STATE_DIR:
            continue
        # Parse date from filename (YYYY-MM-DD-rest.jsonl)
        name = p.name
        date_part = name[:10]
        try:
            file_date = datetime.date.fromisoformat(date_part)
        except ValueError:
            continue
        if file_date <= cutoff:
            count += 1
            if not dry_run:
                shutil.move(str(p), str(archive_dir / p.name))

    if dry_run:
        return f"Would archive {count} files"
    return f"Archived {count} files"


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="JSONL decision log")
    sub = parser.add_subparsers(dest="command")

    # log
    p_log = sub.add_parser("log")
    p_log.add_argument("agent")
    p_log.add_argument("type")
    p_log.add_argument("content")
    p_log.add_argument("--severity")
    p_log.add_argument("--refs")
    p_log.add_argument("--target")

    # read
    p_read = sub.add_parser("read")
    p_read.add_argument("--last", type=int)
    p_read.add_argument("--type", dest="entry_type")
    p_read.add_argument("--agent")
    p_read.add_argument("--severity")
    p_read.add_argument("--json", action="store_true")

    # archive
    p_archive = sub.add_parser("archive")
    p_archive.add_argument("--days", type=int, default=30)
    p_archive.add_argument("--dry-run", action="store_true")

    args = parser.parse_args(argv)

    if args.command == "log":
        refs = args.refs.split(",") if args.refs else None
        log_entry(args.agent, args.type, args.content,
                  severity=args.severity, refs=refs, target=args.target)

    elif args.command == "read":
        output = read_entries(
            last=args.last,
            entry_type=args.entry_type,
            agent=args.agent,
            severity=args.severity,
            as_json=args.json,
        )
        if output:
            print(output)

    elif args.command == "archive":
        result = archive(days=args.days, dry_run=args.dry_run)
        print(result)

    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
