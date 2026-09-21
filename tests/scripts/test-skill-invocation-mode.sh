#!/usr/bin/env bash
# t-3348: /brana:ship must be startable by Claude through the Skill tool.
# `disable-model-invocation: true` made Claude answer "ask the user to run it themselves",
# so a plain "ship it" stalled. Unlocked by operator decision 2026-09-20, same shape as
# challenge (t-3228). The safety net is ship's own mandatory AskUserQuestion gates
# (pre-flight, Gate 3, merge) — not the flag, which only blocks the Skill tool and is
# a friction nudge (docs/architecture/skills.md, ADR-076 #3).
#
# Part B is the root-cause guard: docs/architecture/skills.md keeps an audit table of
# every skill's invocation mode. Flipping a flag without flipping its row (the manual
# chore t-3228 needed) silently drifts the table from the frontmatter. This fails on
# any mismatch, so the next flip cannot forget the docs.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILLS="$ROOT/system/skills"
DOC="$ROOT/docs/architecture/skills.md"
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# frontmatter flag: true only if `disable-model-invocation: true` is inside the first --- block
flagged() {
    awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; next} n==1 && /^disable-model-invocation:[[:space:]]*true/{f=1} n>=2{exit} END{exit !f}' "$1"
}

echo "=== Part A: ship is model-invocable ==="
if flagged "$SKILLS/ship/SKILL.md"; then
    bad "ship SKILL.md still sets disable-model-invocation: true"
else
    ok "ship SKILL.md does not block the Skill tool"
fi
# The unlock is only acceptable while ship still gates itself.
grep -q "Never auto-deploy without user confirmation" "$SKILLS/ship/SKILL.md" \
    && ok "ship still states 'never auto-deploy without user confirmation'" \
    || bad "ship lost its never-auto-deploy rule — do not unlock without it"
GATES=$(grep -c "AskUserQuestion" "$SKILLS/ship/SKILL.md")
[ "$GATES" -ge 3 ] && ok "ship keeps its AskUserQuestion gates ($GATES references)" || bad "ship has too few AskUserQuestion gates ($GATES)"

# The gate this whole unlock rests on must be REAL, not prose in a docs table. Gate 3
# (2026-09-21) found that after one up-front 'Deploy?' prompt, push/merge/bootstrap ran
# unattended: no merge gate existed. Counting AskUserQuestion strings cannot see that, so
# assert the merge gate's position (before `gh pr merge`) and that it fails closed.
SHIP="$SKILLS/ship/SKILL.md"
GATE_LINE=$(grep -n "\*\*Merge gate (mandatory" "$SHIP" | head -1 | cut -d: -f1)   # the real gate paragraph, not the Rules bullet
MERGE_LINE=$(grep -n 'gh pr merge "\$PR"' "$SHIP" | head -1 | cut -d: -f1)
if [ -n "$GATE_LINE" ] && [ -n "$MERGE_LINE" ] && [ "$GATE_LINE" -lt "$MERGE_LINE" ]; then
    ok "ship has a Merge gate before 'gh pr merge' (line $GATE_LINE < $MERGE_LINE)"
else
    bad "ship has no Merge gate before 'gh pr merge' (gate=${GATE_LINE:-none}, merge=${MERGE_LINE:-none})"
fi
sed -n "${GATE_LINE:-1},$((${GATE_LINE:-1} + 25))p" "$SHIP" | grep -qiE "fail(s)? closed" \
    && ok "the merge gate fails closed when AskUserQuestion is unavailable" \
    || bad "the merge gate does not state that it fails closed"

echo "=== Part B: docs audit table matches the frontmatter ==="
# Scope to the audit table only: other tables in the doc (e.g. MCP usage) reuse skill names.
AUDIT_ROWS=$(awk '/^\| Skill \| Group \| Classification \| Rationale \|/{t=1; next} t && /^\|/{print; next} t && NF{exit}' "$DOC")
[ -n "$AUDIT_ROWS" ] || { bad "audit table (| Skill | Group | Classification | Rationale |) not found in $DOC"; }
MISMATCH=0; MISSING=0; CHECKED=0
for d in "$SKILLS"/*/; do
    name=$(basename "$d")
    case "$name" in _shared|acquired) continue ;; esac
    [ -f "$d/SKILL.md" ] || continue
    if flagged "$d/SKILL.md"; then actual="user-invoked-only"; else actual="model-invoked"; fi
    row=$(echo "$AUDIT_ROWS" | grep -E "^\| (\*\*)?${name}(\*\*)? \|" | head -1)
    if [ -z "$row" ]; then
        echo "  WARN: $name has no row in the audit table (frontmatter says $actual)"
        MISSING=$((MISSING + 1)); continue
    fi
    CHECKED=$((CHECKED + 1))
    documented=$(echo "$row" | grep -oE "user-invoked-only|model-invoked" | head -1)
    if [ "$documented" != "$actual" ]; then
        bad "$name: docs say '$documented', frontmatter says '$actual'"
        MISMATCH=$((MISMATCH + 1))
    fi
done
[ "$MISMATCH" -eq 0 ] && ok "audit table agrees with frontmatter for all $CHECKED listed skills ($MISSING unlisted)"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
