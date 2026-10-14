#!/usr/bin/env python3
"""Build the frozen recall gold set from labels-v1.tsv (t-3515).

One JSON line per task. Fields:
  task, query (subject + tags, never description/context/notes, so the ticket's own pointer
  text cannot leak into the query), set ("pointed" or "read"), gold (note slugs), started.

Usage: build_gold.py <labels-v1.tsv> <completed.json> > gold-v1.jsonl
"""
import json
import sys


def main():
    labels = [l.rstrip("\n").split("\t") for l in open(sys.argv[1], encoding="utf-8")
              if l.strip() and not l.startswith("#")]
    raw = open(sys.argv[2], encoding="utf-8").read()
    tasks = {t["id"]: t for t in json.loads(raw[raw.find("["):])}
    gold = {}
    for _, task, slug, label, _ in labels:
        if label not in ("pointed", "read"):
            continue
        g = gold.setdefault((task, label), [])
        if slug not in g:
            g.append(slug)
    for (task, label), slugs in sorted(gold.items(), key=lambda kv: (kv[0][1], int(kv[0][0][2:]))):
        t = tasks[task]
        query = " ".join([t.get("subject") or ""] + list(t.get("tags") or [])).strip()
        print(json.dumps({"task": task, "set": label, "query": query, "gold": slugs,
                          "started": t.get("started") or t.get("created")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
