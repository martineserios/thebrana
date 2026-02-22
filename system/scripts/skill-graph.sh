#!/usr/bin/env bash
# Generate Mermaid flowchart of skill groups and dependencies.
# Reads YAML frontmatter from all SKILL.md files.
# Usage: skill-graph.sh [skills-dir]

SKILLS_DIR="${1:-$(dirname "$0")/../skills}"

if [ ! -d "$SKILLS_DIR" ]; then
    echo "Error: skills directory not found at $SKILLS_DIR" >&2
    exit 1
fi

python3 - "$SKILLS_DIR" <<'PYEOF'
import sys, os, yaml, re
from collections import defaultdict

skills_dir = sys.argv[1]
groups = defaultdict(list)
deps = {}

for name in sorted(os.listdir(skills_dir)):
    skill_file = os.path.join(skills_dir, name, "SKILL.md")
    if not os.path.isfile(skill_file):
        continue

    with open(skill_file) as f:
        content = f.read()

    m = re.match(r'^---\n(.*?)\n---\n', content, re.DOTALL)
    if not m:
        continue

    try:
        fm = yaml.safe_load(m.group(1))
    except yaml.YAMLError:
        continue

    group = fm.get("group", "ungrouped")
    groups[group].append(name)

    skill_deps = fm.get("depends_on", [])
    if skill_deps:
        deps[name] = skill_deps

print("flowchart LR")
print()

for group in sorted(groups):
    print(f"    subgraph {group}")
    for skill in groups[group]:
        print(f"        {skill}")
    print("    end")
    print()

for skill in sorted(deps):
    for dep in deps[skill]:
        print(f"    {dep} --> {skill}")
PYEOF
