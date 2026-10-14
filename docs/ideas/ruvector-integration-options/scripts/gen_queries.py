import json, subprocess

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


out = [{"n": q['n'], "answer_key": q['answer_key'], "vector": embed(q['question'])} for q in QS]
json.dump(out, open('/home/martineserios/.claude/jobs/8e7be6c0/tmp/rv-spike/queries.json', 'w'))
print("wrote", len(out), "query vectors, dim", len(out[0]['vector']))
