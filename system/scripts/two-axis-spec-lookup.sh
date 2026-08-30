#!/usr/bin/env bash
# t-2835 (ADR-084 §4 code-review VENDOR+WRAP): builds the spec brief for the
# vendored code-review skill's Spec sub-agent from a brana task's own fields
# -- never from docs/agents/issue-tracker.md (that file maps tracker *verbs*,
# it is not a spec source; see the two-axis-review adapter doc).
#
# Precedence (first match wins):
#   1. task.acceptance_criteria (non-empty array) -- the approved AC (ADR-079).
#   2. `AC:` -prefixed lines inside task.context (task-convention.md's
#      "AC: prefix" convention) -- used only when acceptance_criteria is empty.
#   3. Neither present -> print the literal "no spec available" and exit 2,
#      a distinct skip signal the adapter reads to skip the Spec sub-agent
#      rather than fabricating a spec or failing the whole review.
#
# A missing/unreadable input file is a hard error (exit 1) -- distinct from
# "task has no spec" (exit 2). Callers must not conflate the two.
#
# Usage: two-axis-spec-lookup.sh <task-json-file>
#   <task-json-file> is one task's JSON (the shape `backlog_get` returns),
#   read from a file rather than piped through the MCP call directly so this
#   logic is testable against fixtures without a live backlog.
set -uo pipefail

task_file="${1:-}"
if [ -z "$task_file" ] || [ ! -f "$task_file" ]; then
  echo "usage: two-axis-spec-lookup.sh <task-json-file>" >&2
  exit 1
fi

python3 - "$task_file" <<'PYEOF'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    task = json.load(f)

ac = task.get("acceptance_criteria") or []
if isinstance(ac, list) and len(ac) > 0:
    for item in ac:
        print(f"- {item}")
    sys.exit(0)

context = task.get("context") or ""
ac_lines = [
    line.strip()[3:].strip()
    for line in context.splitlines()
    if line.strip().startswith("AC:")
]
if ac_lines:
    for line in ac_lines:
        print(f"- {line}")
    sys.exit(0)

print("no spec available")
sys.exit(2)
PYEOF
