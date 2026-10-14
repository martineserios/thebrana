#!/usr/bin/env bash
# recall-eval.sh — hits@5 of `brana recall` on a question set (t-3510).
#
# Usage:  recall-eval.sh <questions.json> [top]
#         BRANA_BIN=/path/to/brana recall-eval.sh questions.json
#
# questions.json: a JSON array of {"n", "question", "answer_key"} objects, where
# answer_key is the memory file stem (e.g. "pattern_claim-inbox-file-before-triage").
# A question is a hit when a MemoryFile result in the top <top> (default 5) has a
# path stem equal to the answer key, or a slug equal to the key with its type
# prefix and timestamp stripped.
#
# The question set is built from private memory files and is deliberately NOT
# committed: pass a path. Prints one summary line and each miss. Exit 0 always
# (a measurement, not a gate); read the line.
#
# Counter-metric (t-3510 gate, F4): the summary also reports the mean share of
# top-<top> results that are knowledge entries (links, feeds) versus memory
# files, and how many calls sat at the 2 s semantic deadline (a dropped leg), so
# a memory-file gain that crowds out knowledge entries is visible.
set -u

QUESTIONS="${1:?usage: recall-eval.sh <questions.json> [top]}"
TOP="${2:-5}"
BRANA_BIN="${BRANA_BIN:-brana}"

[ -f "$QUESTIONS" ] || { echo "recall-eval: no such file: $QUESTIONS" >&2; exit 2; }

python3 -I - "$QUESTIONS" "$TOP" "$BRANA_BIN" <<'PY'
import json, re, statistics, subprocess, sys, time

path, top, brana = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(path))
qs = data if isinstance(data, list) else data.get("questions", [])

def norm(stem):
    # strip "<type>_" prefix and trailing _YYYY-MM-DDTHH-MM-SS
    stem = stem.split("_", 1)[-1] if "_" in stem else stem
    return re.sub(r"_\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}$", "", stem)

import glob, os

def in_scope(key):
    """Recall indexes only the top level of each memory dir; archive subfolders are out."""
    home = os.path.expanduser("~")
    pats = [f"{home}/.claude/memory/{key}.md", f"{home}/.claude/projects/*/memory/{key}.md"]
    return any(glob.glob(p) for p in pats)

hits, lat, misses, reach, reach_hits = 0, [], [], 0, 0
mem_share, kn_share = [], []
for q in qs:
    key = q["answer_key"]
    scoped = in_scope(key)
    reach += scoped
    t = time.time()
    p = subprocess.run([brana, "recall", q["question"], "--top", top, "--json"],
                       capture_output=True, text=True)
    lat.append(time.time() - t)
    try:
        res = json.loads(p.stdout)
    except Exception:
        res = []
    stems, slugs = [], []
    kinds = [next(iter(r.get("doc") or {"?": 0})) for r in res]
    if kinds:
        mem_share.append(kinds.count("MemoryFile") / len(kinds))
        kn_share.append(kinds.count("KnowledgeEntry") / len(kinds))
    for r in res:
        mf = r["doc"].get("MemoryFile")
        if mf:
            stems.append(mf["path"].rsplit("/", 1)[-1].rsplit(".md", 1)[0])
            slugs.append(mf["slug"])
    ok = key in stems or norm(key) in slugs
    hits += ok
    reach_hits += ok and scoped
    if not ok:
        misses.append((q.get("n"), key, stems[:2], scoped))

at_deadline = sum(1 for x in lat if x >= 2.0)
mix = (f"| top-{top} mix: memory {statistics.mean(mem_share):.0%} / knowledge {statistics.mean(kn_share):.0%} "
       if mem_share else "| top-{top} mix: n/a ")
print(f"recall-eval: hits@{top} = {hits}/{len(qs)} | in-scope {reach_hits}/{reach} "
      f"{mix}| median latency {statistics.median(lat):.2f}s ({at_deadline} at the 2 s deadline) | bin={brana}")
for n, key, got, scoped in misses:
    tag = "" if scoped else "  [out of scope: file not at top level of a memory dir]"
    print(f"  miss #{n}: want {key}  got {got}{tag}")
PY
