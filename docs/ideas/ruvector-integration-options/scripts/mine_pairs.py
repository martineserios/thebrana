import glob, json, os, re
from collections import Counter

raw = open('/home/martineserios/.claude/jobs/8e7be6c0/tmp/completed.json').read()
i = raw.find('[')
tasks, _ = json.JSONDecoder().raw_decode(raw[i:])
tasks = tasks if isinstance(tasks, list) else tasks.get('tasks', [])

files = [f for f in glob.glob('/home/martineserios/.claude/projects/*/memory/*.md')
         + glob.glob('/home/martineserios/.claude/memory/*.md') if not f.endswith('/MEMORY.md')]


def norm(stem):
    stem = re.sub(r'_\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}$', '', stem)
    return stem.split('_', 1)[-1] if '_' in stem else stem


slugs = {}
for f in files:
    s = norm(os.path.basename(f)[:-3])
    if len(s) >= 18:          # long enough to avoid accidental matches
        slugs.setdefault(s, f)

paired, pairs_total, per_task = 0, 0, []
for t in tasks:
    blob = ' '.join(str(t.get(k) or '') for k in ('context', 'notes', 'description'))
    hit = {s for s in slugs if s in blob}
    if hit:
        paired += 1
        pairs_total += len(hit)
        per_task.append((t['id'], len(hit)))

print("completed tasks:", len(tasks))
print("tasks whose context/notes/description cite >=1 memory note by slug:", paired)
print("total task->note citations:", pairs_total)
print("citations per citing task: median", sorted(c for _, c in per_task)[len(per_task) // 2] if per_task else 0,
      "max", max((c for _, c in per_task), default=0))
print("tasks citing >=2 distinct notes (usable as multi-note 'context bundle' gold):", sum(1 for _, c in per_task if c >= 2))
types = Counter()
for t in tasks:
    if any(s in ' '.join(str(t.get(k) or '') for k in ('context', 'notes')) for s in slugs):
        types[t.get('kind')] += 1
print("by kind:", types.most_common(6))
