#!/usr/bin/env python3
"""learn-sweep — show only UNPROCESSED daily-summary learnings, then mark them done.

Marathon learning loop (keeps "run the learning process" cost O(new), not O(all)):
  1. python3 ~/.claude/scripts/learn-sweep.py          # list new (unrouted) entries
  2. <route the listed entries into memory/ by hand>
  3. python3 ~/.claude/scripts/learn-sweep.py --commit  # mark everything shown as routed

A cursor file (~/.claude/sessions/.learned-cursor) holds the q-IDs already routed
to memory. Each run diffs the q-IDs in daily-summary-*.md against the cursor and
prints only the delta. q-IDs are stable content hashes, so re-generated summaries
are safe (an already-routed entry never re-surfaces).

Modes:
  (default)   list unprocessed entries (full block text), newest summary last
  --commit    append all currently-unprocessed q-IDs to the cursor (routing done)
  --seed      baseline: mark ALL q-IDs in all summaries as processed (one-time)
  --count     print "<n> unprocessed / <total> total"

Env:
  LEARN_SWEEP_SESSIONS   override the sessions dir (default ~/.claude/sessions).
                         Used by the test suite for hermetic runs.
"""
import os
import re
import sys
import pathlib
import datetime

SESSIONS = pathlib.Path(
    os.environ.get("LEARN_SWEEP_SESSIONS", pathlib.Path.home() / ".claude" / "sessions")
)
CURSOR = SESSIONS / ".learned-cursor"
QID = re.compile(r"entry (q-[0-9a-f]+)")
HEADER = "# learn-sweep cursor — q-IDs already routed to memory\n"


def load_cursor() -> set[str]:
    if not CURSOR.exists():
        return set()
    return {
        ln.split()[0]
        for ln in CURSOR.read_text().splitlines()
        if ln.strip() and not ln.startswith("#")
    }


def all_summaries() -> list[pathlib.Path]:
    return sorted(SESSIONS.glob("daily-summary-*.md"))


def blocks(text: str):
    """Yield (qid, block_text) for each '## ... — entry q-...' section."""
    for part in re.split(r"(?=^## )", text, flags=re.M):
        m = QID.search(part)
        if m:
            yield m.group(1), part.strip()


def collect() -> dict[str, tuple[str, str]]:
    """qid -> (summary_name, block_text); first occurrence wins, file order preserved."""
    out: dict[str, tuple[str, str]] = {}
    for f in all_summaries():
        for qid, block in blocks(f.read_text()):
            out.setdefault(qid, (f.name, block))
    return out


def append_cursor(qids, note: str) -> None:
    if not qids:
        # still ensure the file exists so --seed/--commit on empty state is idempotent
        if not CURSOR.exists():
            CURSOR.write_text(HEADER)
        return
    stamp = datetime.date.today().isoformat()
    if not CURSOR.exists():
        CURSOR.write_text(HEADER)
    with CURSOR.open("a") as fh:
        for q in sorted(qids):
            fh.write(f"{q}  {stamp}  {note}\n")


def main() -> None:
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    done = load_cursor()
    items = collect()
    unprocessed = {q: v for q, v in items.items() if q not in done}

    if arg == "--seed":
        append_cursor(set(items) - done, "seed-baseline")
        print(f"seeded baseline: {len(items) - len(done)} q-IDs marked processed "
              f"({len(items)} total).")
        return
    if arg == "--commit":
        append_cursor(set(unprocessed), "routed")
        print(f"committed: {len(unprocessed)} q-IDs marked routed.")
        return
    if arg == "--count":
        print(f"{len(unprocessed)} unprocessed / {len(items)} total")
        return

    if not unprocessed:
        print(f"OK — 0 unprocessed ({len(items)} total, all routed).")
        return
    print(f"# {len(unprocessed)} unprocessed entries (of {len(items)} total)\n")
    for q, (fname, block) in unprocessed.items():
        print(block)
        print(f"\n^ [{fname} :: {q}]\n{'-' * 70}")


if __name__ == "__main__":
    main()
