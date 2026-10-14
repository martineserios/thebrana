import json, math, sqlite3, struct, subprocess, sys

DB = 'file:/home/martineserios/.claude/jobs/8e7be6c0/tmp/home/.claude/memory/knowledge.db?mode=ro'
RF = '/home/martineserios/.claude/scripts/ruflo-cli.sh'
QS = json.load(open('/home/martineserios/ruflo-clean/questions.json'))
QS = QS if isinstance(QS, list) else QS.get('questions', QS)


def embed(text):
    if text.startswith('-'):
        text = ' ' + text
    p = subprocess.run([RF, 'embeddings', 'generate', '-t', text, '-o', 'json'],
                       capture_output=True, text=True, timeout=90)
    i = p.stdout.find('{')
    return json.loads(p.stdout[i:].strip())['embedding']


def blob(b):
    return struct.unpack('<%df' % (len(b) // 4), b)


def cos(a, b):
    d = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    return d / (na * nb) if na and nb else 0.0


db = sqlite3.connect(DB, uri=True)
rows = [(k, s, blob(v)) for k, s, v in db.execute("select key, source, vec from knowledge")]
print("rows", len(rows), "memory-file", sum(1 for r in rows if r[1] == 'memory-file'))

only = set(sys.argv[1:])  # optional question numbers
for q in QS:
    if only and str(q['n']) not in only:
        continue
    key = q['answer_key']
    qv = embed(q['question'])
    scored = sorted(((cos(qv, v), k, s) for k, s, v in rows), reverse=True)
    mem = [(c, k) for c, k, s in scored if s == 'memory-file']
    # answer row: memory-file whose path stem equals the answer key
    def is_ans(k):
        return k.rsplit('/', 1)[-1].rsplit('.md', 1)[0] == key
    r_all = next((i + 1 for i, (c, k, s) in enumerate(scored) if s == 'memory-file' and is_ans(k)), None)
    r_mem = next((i + 1 for i, (c, k) in enumerate(mem) if is_ans(k)), None)
    sc = next((c for c, k, s in scored if s == 'memory-file' and is_ans(k)), None)
    top_nonmem = next(((c, k) for c, k, s in scored if s != 'memory-file'), (0, ''))
    print("#%-2s rank_all=%-5s rank_memfiles=%-4s score=%s top1_all=%.2f(%s) top1_nonmem=%.2f"
          % (q['n'], r_all, r_mem, None if sc is None else round(sc, 3), scored[0][0],
             'mem' if scored[0][2] == 'memory-file' else 'knw', top_nonmem[0]))
