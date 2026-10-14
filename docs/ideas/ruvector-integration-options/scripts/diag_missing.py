import sqlite3, glob, os, subprocess, json
from collections import Counter

DB = 'file:/home/martineserios/.claude/jobs/8e7be6c0/tmp/home/.claude/memory/knowledge.db?mode=ro'
db = sqlite3.connect(DB, uri=True)
have = {r[0] for r in db.execute("select key from knowledge where source='memory-file'")}
files = sorted(glob.glob('/home/martineserios/.claude/projects/*/memory/*.md')
               + glob.glob('/home/martineserios/.claude/memory/*.md'))
files = [f for f in files if not f.endswith('/MEMORY.md')]
miss = [f for f in files if 'memory-file:' + f not in have]
print("files", len(files), "have", len(have), "missing", len(miss))
print("missing by project dir:", Counter(f.split('/')[-3][:45] for f in miss if '/projects/' in f).most_common(4))
print("missing starts with ---:", sum(open(f).read().startswith('---') for f in miss), "of", len(miss))
print("have starts with ---:", sum(open(k[len('memory-file:'):]).read().startswith('---') for k in have), "of", len(have))
print("missing sizes (median chars):", sorted(len(open(f).read()) for f in miss)[len(miss)//2])
for f in miss[:3]:
    t = open(f).read()[:1500]
    p = subprocess.run(['/home/martineserios/.claude/scripts/ruflo-cli.sh', 'embeddings', 'generate',
                        '-t', t, '-o', 'json'], capture_output=True, text=True, timeout=90)
    out = p.stdout
    i = out.find('{')
    print(os.path.basename(f), "rc", p.returncode, "len", len(t), "json_at", i,
          "| stderr tail:", p.stderr[-100:].replace("\n", " "))
    if i >= 0:
        try:
            v = json.loads(out[i:].strip())
            e = v.get('embedding')
            print("  keys", list(v)[:6], "dim", len(e) if e else None)
        except Exception as ex:
            print("  json parse fail:", str(ex)[:80], "|", out[i:i + 140].replace("\n", " "))
    else:
        print("  no json; stdout head:", out[:200].replace("\n", " "))
