#!/usr/bin/env python3
"""Score a recall command against the frozen gold set (t-3515; reused by t-3518).

For every gold task, runs `<brana> recall <query> --top 20 --json` and finds the rank of each
gold slug among memory-file hits (dated suffixes stripped). Reports per set:
  hit@5, hit@8   share of tasks with at least one gold note in the top K
  MRR            mean reciprocal rank of the first gold note (0 when absent from the top 20)
  recall@8       share of gold notes found in the top 8
Writes one JSON line per task to argv[3] for later comparison.

Usage: score_baseline.py <gold-v1.jsonl> <brana-binary> <per-task-out.jsonl>
"""
import json
import re
import subprocess
import sys


def slug_of(hit):
    doc = hit.get("doc") or {}
    mf = doc.get("MemoryFile")
    if not mf:
        return None
    return re.sub(r"_\d{4}-\d{2}-\d{2}(T\d{2}-\d{2}-\d{2})?$", "", mf.get("slug") or "")


def main():
    gold = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
    out = open(sys.argv[3], "w", encoding="utf-8")
    stats = {}
    for g in gold:
        r = subprocess.run([sys.argv[2], "recall", g["query"], "--top", "20", "--json"],
                           capture_output=True, text=True, timeout=60)
        try:
            hits = json.loads(r.stdout or "[]")
        except json.JSONDecodeError:
            hits = []
        ranked = [slug_of(h) for h in hits]
        ranks = {s: (ranked.index(s) + 1 if s in ranked else None) for s in g["gold"]}
        first = min([x for x in ranks.values() if x], default=None)
        row = {"task": g["task"], "set": g["set"], "ranks": ranks, "first": first,
               "n_hits": len(hits), "exit": r.returncode}
        out.write(json.dumps(row) + "\n")
        s = stats.setdefault(g["set"], {"n": 0, "h5": 0, "h8": 0, "rr": 0.0, "found8": 0, "golds": 0})
        s["n"] += 1
        s["h5"] += bool(first and first <= 5)
        s["h8"] += bool(first and first <= 8)
        s["rr"] += 1.0 / first if first else 0.0
        s["golds"] += len(g["gold"])
        s["found8"] += sum(1 for x in ranks.values() if x and x <= 8)
    for name, s in stats.items():
        print(f"{name}: n={s['n']} hit@5={s['h5'] / s['n']:.3f} hit@8={s['h8'] / s['n']:.3f} "
              f"MRR={s['rr'] / s['n']:.3f} recall@8={s['found8'] / s['golds']:.3f} (gold notes {s['golds']})")


if __name__ == "__main__":
    main()
