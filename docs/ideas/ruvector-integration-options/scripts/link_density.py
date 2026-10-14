import glob, re, os
from collections import Counter

files = [f for f in glob.glob('/home/martineserios/.claude/projects/*/memory/*.md')
         + glob.glob('/home/martineserios/.claude/memory/*.md') if not f.endswith('/MEMORY.md')]
link_re = re.compile(r'\[\[([^\]\|#]+)')
stem = lambda p: os.path.basename(p)[:-3]


def norm(s):
    s = s.strip()
    s = re.sub(r'_\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}$', '', s)
    return s.split('_', 1)[-1] if '_' in s else s


by_norm = {}
for f in files:
    by_norm.setdefault(norm(stem(f)), []).append(f)

out_deg, resolved, total = {}, 0, 0
for f in files:
    targets = link_re.findall(open(f, errors='ignore').read())
    out_deg[f] = len(targets)
    for t in targets:
        total += 1
        if norm(t) in by_norm or t.strip() in {stem(x) for x in files}:
            resolved += 1

with_links = sum(1 for d in out_deg.values() if d)
print("memory files:", len(files))
print("files with >=1 [[link]]:", with_links, "(%.0f%%)" % (100 * with_links / len(files)))
print("total [[links]]:", total, "| resolving to an existing note:", resolved, "(%.0f%%)" % (100 * resolved / max(total, 1)))
dist = Counter(min(d, 6) for d in out_deg.values())
print("outgoing links per file (0..6+):", [dist.get(i, 0) for i in range(7)])
by_type = Counter()
for f in files:
    t = stem(f).split('_', 1)[0] if '_' in stem(f) else '(none)'
    by_type[t] += 1
print("note types:", by_type.most_common(8))
