#!/usr/bin/env bash
# Test: INCONCLUSIVE as a first-class verdict (t-3494).
#
# WHAT IS UNDER TEST. The judged layer's prose contracts are machine-read (ADR-081 D2):
# `brana backlog stacked-verdict` parses `Evaluator: {verdict}` / `Challenger: {verdict}`
# lines out of task notes, and the gates tell the agents which exact words to write.
# INCONCLUSIVE ("the evidence does not decide this") must exist on every surface that
# emits or consumes a verdict, or it degrades to PASS WITH GAPS / PROCEED WITH CHANGES
# (auto-advances) or to `0 judged` (silently dropped). Each check is a must-fire
# fixture: the surface must name the verdict in the one place the contract lives.
#
# Run: bash tests/procedures/test-inconclusive-verdict.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0; TOTAL=0

assert_grep() {
    local desc="$1" pattern="$2" file="$3"
    TOTAL=$((TOTAL + 1))
    if grep -qE -- "$pattern" "$ROOT/$file"; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — pattern [$pattern] not found in $file"; FAIL=$((FAIL + 1))
    fi
}

echo "Surface 1 — /brana:challenge and the challenger agent"
assert_grep "challenger.md verdict set lists INCONCLUSIVE" \
    'PROCEED \| PROCEED WITH CHANGES \| RECONSIDER \| INCONCLUSIVE' system/agents/challenger.md
assert_grep "CALIBRATION.md has a verdict rule for INCONCLUSIVE (unverified premise / evidence below threshold)" \
    'INCONCLUSIVE' system/agents/CALIBRATION.md
assert_grep "challenge SKILL.md report verdict line lists INCONCLUSIVE" \
    'PROCEED / PROCEED WITH CHANGES / RECONSIDER / INCONCLUSIVE' system/skills/challenge/SKILL.md
assert_grep "challenge SKILL.md decisions-log step records missing evidence for INCONCLUSIVE" \
    'INCONCLUSIVE.*missing evidence|missing evidence.*INCONCLUSIVE' system/skills/challenge/SKILL.md

echo "Surface 2 — build-evaluator"
assert_grep "build-evaluator.md has a per-criterion UNVERIFIABLE verdict" \
    '\*\*UNVERIFIABLE\*\*' system/agents/build-evaluator.md
assert_grep "build-evaluator.md overall verdict set includes INCONCLUSIVE" \
    'PASS \| PASS WITH GAPS \| FAIL \| INCONCLUSIVE' system/agents/build-evaluator.md
assert_grep "build-evaluator.md INCONCLUSIVE lists the unverifiable AC ids" \
    'INCONCLUSIVE.*(AC ids|criteria ids|list)' system/agents/build-evaluator.md

echo "Surface 3 — the gates that write the machine-read notes line"
assert_grep "challenger-gate.md exact-wording contract includes INCONCLUSIVE" \
    '`PROCEED`, `PROCEED WITH CHANGES`, `RECONSIDER`, or `INCONCLUSIVE`' system/skills/_shared/challenger-gate.md
assert_grep "challenger-gate.md: INCONCLUSIVE blocks CLOSE (never auto-advances)" \
    'INCONCLUSIVE.*CLOSE blocked' system/skills/_shared/challenger-gate.md
assert_grep "verify-gates.md verdict table has an INCONCLUSIVE row that blocks" \
    '\*\*INCONCLUSIVE\*\*.*Block' system/skills/build/phases/verify-gates.md
assert_grep "verify-gates.md exact-wording contract includes INCONCLUSIVE" \
    '`PASS`, `PASS WITH GAPS`, `FAIL`, or `INCONCLUSIVE`' system/skills/build/phases/verify-gates.md
assert_grep "executor-brief.md return contract offers INCONCLUSIVE" \
    'PASS \| PASS WITH GAPS \| FAIL \| INCONCLUSIVE' system/skills/_shared/executor-brief.md

echo "Surface 4 — the parser's documented contract"
assert_grep "ADR-081 parsing contract names INCONCLUSIVE for both sources" \
    'INCONCLUSIVE' docs/architecture/decisions/ADR-081-stacked-verdict-evidence-composition.md
assert_grep "stacked_verdict.rs parses INCONCLUSIVE" \
    'INCONCLUSIVE' system/cli/rust/crates/brana-cli/src/commands/stacked_verdict.rs

echo ""
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
[ "$FAIL" -eq 0 ]
