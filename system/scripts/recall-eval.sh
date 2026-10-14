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

hits, lat, misses = 0, [], []
for q in qs:
    key = q["answer_key"]
    t = time.time()
    p = subprocess.run([brana, "recall", q["question"], "--top", top, "--json"],
                       capture_output=True, text=True)
    lat.append(time.time() - t)
    try:
        res = json.loads(p.stdout)
    except Exception:
        res = []
    stems, slugs = [], []
    for r in res:
        mf = r["doc"].get("MemoryFile")
        if mf:
            stems.append(mf["path"].rsplit("/", 1)[-1].rsplit(".md", 1)[0])
            slugs.append(mf["slug"])
    ok = key in stems or norm(key) in slugs
    hits += ok
    if not ok:
        misses.append((q.get("n"), key, stems[:2]))

print(f"recall-eval: hits@{top} = {hits}/{len(qs)} | median latency {statistics.median(lat):.2f}s | bin={brana}")
for n, key, got in misses:
    print(f"  miss #{n}: want {key}  got {got}")
PY
