#!/usr/bin/env bash
# Consistency of the ADR-097 / ADR-098 document family (t-3506).
#
# WHAT IS UNDER TEST. ADR-097 made the upstream band standing; ADR-098 (2026-10-09) retired it and
# cancelled its P0/P1 tasks. The 2026-10-09 ship's Gate 3 found the family still carrying the pre-098
# text: `status: draft`, "(proposed …)", "P1 (not yet created)", "pending ADR-097", "penciled", plan rows
# citing the cancelled t-3489 / t-3495 as if live, a research doc with §6 before §5, stale assertion
# counts in cockpit.md, and capture fixtures embedding /tmp/claude-1000/<session-uuid> paths. Each check
# is anchored to a status line / table row / heading, never to a bare word a comment would satisfy.
#
# Run: bash tests/scripts/test-adr-097-family-consistency.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }
rd() { cat "$ROOT/$1"; }

IDEA=docs/ideas/pocock-v13-adoption.md
BUMP=docs/architecture/features/upstream-band-pin-bump.md
PRB=docs/architecture/features/pr-body-organ.md
A84=docs/architecture/decisions/ADR-084-upstream-skill-band-vendored-pocock-skills.md
A97=docs/architecture/decisions/ADR-097-upstream-band-standing-v1-3.md
RES=docs/research/2026-10-07-pocock-recheck.md

echo "=== test-adr-097-family-consistency.sh ==="
echo "--- the idea doc"
assert "frontmatter status is superseded (was draft)" yes "$(has $'\nstatus: superseded\n' "$(rd $IDEA | head -8)")"
assert "no '(proposed 2026-10-07)' pointer to ADR-097" no "$(has '(proposed 2026-10-07)' "$(rd $IDEA)")"
assert "no 'penciled, not created' heading" no "$(has 'penciled, not created' "$(rd $IDEA)")"
assert "points at ADR-098 in its relates-to" yes "$(has 'ADR-098' "$(rd $IDEA | head -14)")"
assert "the original P1-P10 plan heading says it is superseded history" yes "$(printf '%s\n' "$(rd $IDEA)" | grep -E '^## ' | grep -q 'Original proposed plan.*superseded' && echo yes || echo no)"
assert "the open-questions heading says they were answered" yes "$(printf '%s\n' "$(rd $IDEA)" | grep -E '^## ' | grep -q 'Open questions.*answered' && echo yes || echo no)"
assert "the P0 (t-3489) row is marked cancelled" yes "$(printf '%s\n' "$(rd $IDEA)" | grep -E '^\| P0 \(t-3489\)' | grep -q -i 'cancelled' && echo yes || echo no)"
assert "the P1 (t-3495) row is marked cancelled" yes "$(printf '%s\n' "$(rd $IDEA)" | grep -E '^\| P1 \(t-3495\)' | grep -q -i 'cancelled' && echo yes || echo no)"
assert "the shape item that vendors \`pr\` as an organ is marked withdrawn" yes "$(printf '%s\n' "$(rd $IDEA)" | grep -E '^3\. \*\*Admit' -A6 | grep -q -i 'withdrawn' && echo yes || echo no)"
assert "the 'sync the integration tip' invariant is marked reversed" yes "$(printf '%s\n' "$(rd $IDEA)" | grep -E 'sync the integration tip' -A3 | grep -q -i 'reversed' && echo yes || echo no)"

echo "--- upstream-band-pin-bump.md"
assert "Status line says superseded by ADR-098" yes "$(printf '%s\n' "$(rd $BUMP)" | grep -E '^\*\*Status:\*\*' | grep -q 'ADR-098' && echo yes || echo no)"
assert "no 'P1 (not yet created)'" no "$(has 'P1 (not yet created)' "$(rd $BUMP)")"
assert "the Task line names t-3495 (cancelled)" yes "$(printf '%s\n' "$(rd $BUMP)" | grep -E '^\*\*Task:\*\*' | grep -q 't-3495' && echo yes || echo no)"
assert "no 'pending ADR-097' in the decision-record heading" no "$(has 'pending ADR-097' "$(rd $BUMP)")"
assert "no 'penciled for P1' acceptance heading" no "$(has 'penciled for P1' "$(rd $BUMP)")"

echo "--- pr-body-organ.md"
assert "Status line names ADR-098 (narrowed)" yes "$(printf '%s\n' "$(rd $PRB)" | grep -E '^\*\*Status:\*\*' | grep -q 'ADR-098' && echo yes || echo no)"
assert "Task line carries the live task id t-3490" yes "$(printf '%s\n' "$(rd $PRB)" | grep -E '^\*\*Task:\*\*' | grep -q 't-3490' && echo yes || echo no)"

echo "--- ADR-084 / ADR-097 headers"
assert "ADR-084 frontmatter records that ADR-098 amends it" yes "$(has 'ADR-098' "$(rd $A84 | head -6)")"
assert "ADR-084 Status line has no bare 'proposed in ADR-097' without the retirement" yes "$(printf '%s\n' "$(rd $A84)" | grep -E '^\*\*Status:\*\*' | grep -q 'retired by' && echo yes || echo no)"
assert "ADR-097 frontmatter status is superseded" yes "$(has $'\nstatus: superseded\n' "$(rd $A97 | head -4)")"
assert "ADR-097 Tasks line marks t-3489 cancelled" yes "$(printf '%s\n' "$(rd $A97)" | grep -E '^\*\*Tasks:\*\*' | grep -q 't-3489 (cancelled' && echo yes || echo no)"
assert "ADR-097 Tasks line marks t-3495 cancelled" yes "$(printf '%s\n' "$(rd $A97)" | grep -E '^\*\*Tasks:\*\*' | grep -q 't-3495 (cancelled' && echo yes || echo no)"
assert "ADR-097 plan row P0 (t-3489) says cancelled, superseded by ADR-098" yes "$(printf '%s\n' "$(rd $A97)" | grep -E '^\| P0 \(t-3489\)' | grep -q 'cancelled.*ADR-098' && echo yes || echo no)"
assert "ADR-097 plan row P1 (t-3495) says cancelled, superseded by ADR-098" yes "$(printf '%s\n' "$(rd $A97)" | grep -E '^\| P1 \(t-3495\)' | grep -q 'cancelled.*ADR-098' && echo yes || echo no)"
for r in "P3 (t-3490)" "P4 (t-3491)" "P7 (t-3492)"; do
    assert "ADR-097 plan keeps the live row $r" yes "$(printf '%s\n' "$(rd $A97)" | grep -qF "| $r" && echo yes || echo no)"
done

echo "--- research doc order, cockpit counts, README row"
assert "research doc: §5 precedes §6" yes "$(python3 -I - "$ROOT/$RES" <<'PY'
import re, sys
heads = [m.group(1) for m in re.finditer(r"^## (\d+)\.", open(sys.argv[1]).read(), re.M)]
print("yes" if heads == sorted(heads, key=int) else "no")
PY
)"
assert "cockpit.md has no stale '32 assertions' / '105 assertions' counts" no "$(printf '%s\n' "$(rd docs/architecture/features/cockpit.md)" | grep -qE '\b(32|105) assertions\b' && echo yes || echo no)"
assert "docs/README.md cockpit row names 7i and Check 77c" yes "$(printf '%s\n' "$(rd docs/README.md)" | grep -E '^\| \[cockpit.md\]' | grep -q '7i' && printf '%s\n' "$(rd docs/README.md)" | grep -E '^\| \[cockpit.md\]' | grep -q '77c' && echo yes || echo no)"

echo "--- capture fixtures carry no session paths"
assert "no /tmp/claude-1000/<session-uuid> path under the t-3493 captures" 0 "$(grep -rl '/tmp/claude-1000' "$ROOT/tests/fixtures/mods/captures/t-3493-model-billing" 2>/dev/null | wc -l | tr -d ' ')"
assert "no /tmp/claude-1000 path anywhere under tests/fixtures" 0 "$(grep -rl '/tmp/claude-1000' "$ROOT/tests/fixtures" 2>/dev/null | wc -l | tr -d ' ')"

echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
