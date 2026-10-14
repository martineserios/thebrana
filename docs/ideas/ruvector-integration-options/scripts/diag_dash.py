import subprocess, json

RF = '/home/martineserios/.claude/scripts/ruflo-cli.sh'


def run(text):
    p = subprocess.run([RF, 'embeddings', 'generate', '-t', text, '-o', 'json'],
                       capture_output=True, text=True, timeout=90)
    i = p.stdout.find('{')
    if i < 0:
        return "FAIL rc=%d | %s" % (p.returncode, p.stderr[-90:].replace("\n", " "))
    try:
        e = json.loads(p.stdout[i:].strip()).get('embedding')
        return "OK dim=%s" % (len(e) if e else None)
    except Exception as ex:
        return "PARSE-FAIL " + str(ex)[:60]


cases = {
    "plain": "hello world",
    "frontmatter": "---\nname: x\ndescription: d\n---\nbody text",
    "leading-space-frontmatter": " ---\nname: x\ndescription: d\n---\nbody text",
    "leading-dash-word": "-foo bar",
    "leading-space-dash-word": " -foo bar",
    "consolidation-log-head": open('/home/martineserios/.claude/memory/consolidation-log.md').read()[:1500],
    "consolidation-log-head-space": " " + open('/home/martineserios/.claude/memory/consolidation-log.md').read()[:1500],
}
for k, v in cases.items():
    print("%-30s %s" % (k, run(v)))
