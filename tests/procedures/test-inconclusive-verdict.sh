#!/usr/bin/env bash
# Test: INCONCLUSIVE as a first-class verdict (t-3494).
#
# WHAT IS UNDER TEST. The judged layer's prose contracts are machine-read (ADR-081 D2):
# `brana backlog stacked-verdict` parses `Evaluator: {verdict}` / `Challenger: {verdict}`
# lines out of task notes, and the gates tell the agents which exact words to write.
# INCONCLUSIVE ("the evidence does not decide this") must exist on every surface that
# emits or consumes a verdict, or it degrades to PASS WITH GAPS / PROCEED WITH CHANGES
# (auto-advances) or to `0 judged` (silently dropped). Each check is anchored to the
# contract line itself (the rule text, the regex, the match arm), never to a bare word
# that a comment would satisfy.
#
# NOT COVERED HERE: whether an agent actually emits INCONCLUSIVE on a given input is
# model behaviour and is not grep-testable. The parser's behaviour on the emitted lines
# lives in the Rust tests (stacked_verdict.rs unit tests, stacked_verdict_smoke.rs).
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

assert_no_grep() {
    local desc="$1" pattern="$2" file="$3"
    TOTAL=$((TOTAL + 1))
    if grep -qE -- "$pattern" "$ROOT/$file"; then
        echo "  FAIL: $desc — pattern [$pattern] still present in $file"; FAIL=$((FAIL + 1))
    else
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    fi
}

echo "Surface 1 — /brana:challenge and the challenger agent"
assert_grep "challenger.md verdict set lists INCONCLUSIVE" \
    'PROCEED \| PROCEED WITH CHANGES \| RECONSIDER \| INCONCLUSIVE' system/agents/challenger.md
assert_grep "challenger.md rule: >=4 forces RECONSIDER unless the INCONCLUSIVE rule applies" \
    'forces RECONSIDER.*unless the INCONCLUSIVE rule applies' system/agents/challenger.md
assert_grep "CALIBRATION.md verdict rule names INCONCLUSIVE with its trigger (unverified premise)" \
    '\*\*INCONCLUSIVE\*\*.*unverified' system/agents/CALIBRATION.md
assert_grep "CALIBRATION.md states the precedence over the >=4 rule (both conditions)" \
    'Precedence.*INCONCLUSIVE.*>= ?4.*AND' system/agents/CALIBRATION.md
assert_grep "CALIBRATION.md: non-overridable classes never downgrade to INCONCLUSIVE" \
    '[Nn]on-overridable.*never.*INCONCLUSIVE|never.*INCONCLUSIVE.*[Nn]on-overridable' system/agents/CALIBRATION.md
assert_grep "CALIBRATION.md 'always' rows carry the INCONCLUSIVE exception (untested critical path)" \
    'Untested critical path.*unless the INCONCLUSIVE rule applies' system/agents/CALIBRATION.md
assert_grep "CALIBRATION.md 'always' rows carry the INCONCLUSIVE exception (assumption unvalidated)" \
    'Assumption unvalidated.*unless the INCONCLUSIVE rule applies' system/agents/CALIBRATION.md
assert_grep "CALIBRATION.md has a positive INCONCLUSIVE few-shot" \
    '^### Example [0-9]+: INCONCLUSIVE' system/agents/CALIBRATION.md
assert_grep "CALIBRATION.md has a not-INCONCLUSIVE few-shot" \
    '^### Example [0-9]+: NOT INCONCLUSIVE' system/agents/CALIBRATION.md
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
assert_grep "agents.md evaluator row names UNVERIFIABLE" \
    'build-evaluator.*UNVERIFIABLE' docs/architecture/agents.md

echo "Surface 3 — the gates that write the machine-read notes line"
assert_grep "challenger-gate.md exact-wording contract includes INCONCLUSIVE" \
    '`PROCEED`, `PROCEED WITH CHANGES`, `RECONSIDER`, or `INCONCLUSIVE`' system/skills/_shared/challenger-gate.md
assert_grep "challenger-gate.md: INCONCLUSIVE blocks CLOSE (never auto-advances)" \
    'INCONCLUSIVE.*CLOSE blocked' system/skills/_shared/challenger-gate.md
assert_grep "challenger-gate.md: the INCONCLUSIVE run is iteration 1 of the max-2 cap" \
    'INCONCLUSIVE run (is|counts as) iteration 1' system/skills/_shared/challenger-gate.md
assert_grep "challenger-gate.md: a second INCONCLUSIVE offers override or abandon only" \
    'second INCONCLUSIVE.*override or abandon only' system/skills/_shared/challenger-gate.md
assert_grep "challenger-gate.md: {list} must be single-line without a verdict token" \
    'single-line.*verdict token' system/skills/_shared/challenger-gate.md
assert_grep "verify-gates.md verdict table has an INCONCLUSIVE row that blocks" \
    '\*\*INCONCLUSIVE\*\*.*Block' system/skills/build/phases/verify-gates.md
assert_grep "verify-gates.md exact-wording contract includes INCONCLUSIVE" \
    '`PASS`, `PASS WITH GAPS`, `FAIL`, or `INCONCLUSIVE`' system/skills/build/phases/verify-gates.md
assert_grep "verify-gates.md: {AC ids} must be single-line without a verdict token" \
    'single-line.*verdict token' system/skills/build/phases/verify-gates.md
assert_grep "executor-brief.md scopes INCONCLUSIVE to the two gates (no delegated-executor consumer)" \
    'INCONCLUSIVE is reserved for the (two )?gates' system/skills/_shared/executor-brief.md
assert_no_grep "executor-brief.md generic return contract does not offer INCONCLUSIVE to every executor" \
    'VERDICT: .*PASS \| PASS WITH GAPS \| FAIL \| INCONCLUSIVE' system/skills/_shared/executor-brief.md
assert_grep "executor-brief.md map row quotes the gate verdict set including INCONCLUSIVE" \
    'verify-gates.md.*INCONCLUSIVE' system/skills/_shared/executor-brief.md
assert_grep "judge-sizing.md states INCONCLUSIVE arms no rung signal by design" \
    'INCONCLUSIVE arms no rung signal' system/skills/_shared/judge-sizing.md

echo "Surface 4 — the parser's documented contract"
assert_grep "ADR-081 D2 regex names INCONCLUSIVE on the Evaluator source" \
    '\^Evaluator: \(PASS\|PASS WITH GAPS\|FAIL\|INCONCLUSIVE\)' docs/architecture/decisions/ADR-081-stacked-verdict-evidence-composition.md
assert_grep "ADR-081 D2 regex names INCONCLUSIVE on the Challenger source" \
    '\^Challenger: \(PROCEED\(\?: WITH CHANGES\)\?\|RECONSIDER\|INCONCLUSIVE\)' docs/architecture/decisions/ADR-081-stacked-verdict-evidence-composition.md
assert_grep "ADR-049 cross-references the ADR-081 INCONCLUSIVE amendment" \
    'INCONCLUSIVE.*ADR-081|ADR-081.*INCONCLUSIVE' docs/architecture/decisions/ADR-049-mandatory-challenger-gate-build-close.md
assert_grep "stacked_verdict.rs has the Judged::Inconclusive match arm" \
    'Some\(Judged::Inconclusive\) => counts\.inconclusive \+= 1' system/cli/rust/crates/brana-cli/src/commands/stacked_verdict.rs
assert_grep "stacked_verdict.rs parses INCONCLUSIVE on the Evaluator source" \
    'evaluator = Some\(Judged::Inconclusive\)' system/cli/rust/crates/brana-cli/src/commands/stacked_verdict.rs
assert_grep "stacked_verdict.rs parses INCONCLUSIVE on the Challenger source" \
    'challenger = Some\(Judged::Inconclusive\)' system/cli/rust/crates/brana-cli/src/commands/stacked_verdict.rs

echo ""
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
[ "$FAIL" -eq 0 ]
