#!/usr/bin/env python3
"""Mine task -> memory-note citations as candidate recall gold (t-3515).

v2 of docs/ideas/ruvector-integration-options/scripts/mine_pairs.py. Differences:
- reads a `brana backlog query --status completed --output json` export given as argv[1]
  (the v1 script read a job-tmp export that no longer exists);
- scope is the thebrana project memory dir plus global ~/.claude/memory, top level only,
  so client notes never enter the gold set (ADR-095) and archive*/ stays out (ADR-099 §2);
- every hit is kept per field (description / context / notes) with a quoted window and the
  character offset, so a human can label it pointed / wrote / read;
- the note's earliest known date is recorded (filename date suffix, frontmatter
  created/modified, else file mtime as an upper bound) next to the task's start date.

Output: JSON lines on stdout, one candidate hit per line. Labels are added by hand in a
separate file (gold-v1.jsonl); this script never labels.

Usage: mine_pairs_v2.py <completed.json> > candidates.jsonl
"""
import datetime as dt
import glob
import json
import os
import re
import sys

HOME = os.path.expanduser("~")
SCOPE_DIRS = [
    f"{HOME}/.claude/projects/-home-martineserios-enter-thebrana-thebrana/memory",
    f"{HOME}/.claude/memory",
]
FIELDS = ("description", "context", "notes")
WINDOW = 160
MIN_SLUG = 18  # shorter slugs match by accident


def norm(stem):
    """Strip a dated suffix and the type prefix: pattern_foo_2026-08-01T.. -> foo."""
    stem = re.sub(r"_\d{4}-\d{2}-\d{2}(T\d{2}-\d{2}-\d{2})?$", "", stem)
    return stem.split("_", 1)[-1] if "_" in stem else stem


def note_date(path):
    """Earliest defensible date for a note, and where it came from."""
    m = re.search(r"_(\d{4}-\d{2}-\d{2})(T\d{2}-\d{2}-\d{2})?\.md$", path)
    if m:
        return m.group(1), "filename"
    try:
        head = open(path, encoding="utf-8", errors="replace").read(3000)
    except OSError:
        head = ""
    for key in ("created", "modified"):
        m = re.search(rf"^\s*{key}:\s*\"?(\d{{4}}-\d{{2}}-\d{{2}})", head, re.M)
        if m:
            return m.group(1), f"frontmatter:{key}"
    mtime = dt.datetime.fromtimestamp(os.path.getmtime(path)).date().isoformat()
    return mtime, "mtime-upper-bound"


def load_notes():
    notes = {}
    for d in SCOPE_DIRS:
        for f in glob.glob(os.path.join(d, "*.md")):
            if os.path.basename(f) == "MEMORY.md":
                continue
            stem = os.path.basename(f)[:-3]
            slug = norm(stem)
            if len(slug) < MIN_SLUG:
                continue
            date, src = note_date(f)
            prev = notes.get(slug)
            # several dated files can share a slug; keep the earliest
            if prev is None or date < prev["date"]:
                notes[slug] = {"slug": slug, "file": f, "stem": stem, "date": date, "date_src": src}
    return notes


def main():
    raw = open(sys.argv[1], encoding="utf-8").read()
    tasks = json.loads(raw[raw.find("["):])
    notes = load_notes()
    pattern = re.compile("|".join(re.escape(s) for s in sorted(notes, key=len, reverse=True)))
    for t in tasks:
        for field in FIELDS:
            text = t.get(field) or ""
            if not isinstance(text, str):
                text = json.dumps(text)
            for m in pattern.finditer(text):
                n = notes[m.group(0)]
                a, b = max(0, m.start() - WINDOW), min(len(text), m.end() + WINDOW)
                print(json.dumps({
                    "task": t["id"],
                    "subject": t.get("subject"),
                    "tags": t.get("tags") or [],
                    "kind": t.get("kind"),
                    "started": t.get("started"),
                    "created": t.get("created"),
                    "completed": t.get("completed"),
                    "field": field,
                    "offset": m.start(),
                    "slug": n["slug"],
                    "note_stem": n["stem"],
                    "note_scope": "global" if "/.claude/memory/" in n["file"] else "project",
                    "note_date": n["date"],
                    "note_date_src": n["date_src"],
                    "window": text[a:b].replace("\n", " "),
                }, ensure_ascii=False))


if __name__ == "__main__":
    main()
