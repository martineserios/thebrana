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

echo "Surface 5 — t-3504 hardening: evidence channel, caps, headless, escaping, consumers"
VG=system/skills/build/phases/verify-gates.md
CG=system/skills/_shared/challenger-gate.md
assert_grep "verify-gates.md: the evaluator spawn prompt carries an orchestrator-captured Evidence: block" \
    '^Evidence \(orchestrator-captured, commit \{HEAD_SHA\}\):' "$VG"
assert_grep "verify-gates.md: the Evidence capture step writes the run-state evidence file (keyed by commit)" \
    'run-state/\{task_id\}\.\$HEAD_SHA\.evidence' "$VG"
assert_grep "verify-gates.md: states the evaluator is read-only so Evidence is its only live-run channel" \
    'read-only.*Evidence.*(only|sole) channel' "$VG"
assert_grep "verify-gates.md: evidence is bound to the commit it was captured at (stale evidence is not evidence)" \
    'captured at a different commit.*(stale|re-capture)' "$VG"
assert_grep "verify-gates.md: the evaluator INCONCLUSIVE run is iteration 1 of a max-2 cap" \
    'INCONCLUSIVE run (is|counts as) iteration 1' "$VG"
assert_grep "verify-gates.md: a second evaluator INCONCLUSIVE offers override or abandon only" \
    'second INCONCLUSIVE.*override or abandon only' "$VG"
assert_grep "verify-gates.md: headless/no-AskUserQuestion INCONCLUSIVE = Abandon (blocked), never proceed" \
    '(headless|no AskUserQuestion).*Abandon.*never proceed' "$VG"
assert_grep "verify-gates.md: free text rides on a separate Evaluator-gap: prefix" \
    '^`Evaluator-gap: \{AC ids' "$VG"
assert_no_grep "verify-gates.md: the machine-read Evaluator line no longer carries the AC-id free text" \
    'Evaluator: INCONCLUSIVE \(\{date\}\), \{N\} criteria checked, unverifiable' "$VG"
assert_grep "verify-gates.md: notes writes are one line (the CLI escapes embedded newlines)" \
    'escapes? (embedded )?newlines' "$VG"
assert_grep "challenger-gate.md: headless/no-AskUserQuestion INCONCLUSIVE = Abandon (blocked), never proceed" \
    '(headless|no AskUserQuestion).*Abandon.*never proceed' "$CG"
assert_grep "challenger-gate.md: free text rides on a separate Challenger-gap: prefix" \
    '^`Challenger-gap: \{list' "$CG"
assert_no_grep "challenger-gate.md: the machine-read Challenger line no longer carries the gap free text" \
    'Challenger: INCONCLUSIVE \(\{date\}\), \{N\} finding\(s\), missing evidence' "$CG"
assert_grep "challenger-gate.md: notes writes are one line (the CLI escapes embedded newlines)" \
    'escapes? (embedded )?newlines' "$CG"
assert_grep "ship SKILL Step 1b: an INCONCLUSIVE worker is neither clean nor a finding and blocks the quorum" \
    'INCONCLUSIVE worker.*neither clean nor a finding' system/skills/ship/SKILL.md
assert_grep "ship SKILL: Step 4's CLI install must not be declined (verdict wording reads 0 judged until it lands)" \
    'Step 4.*must not be declined.*0 judged|must not be declined.*0 judged' system/skills/ship/SKILL.md
assert_grep "build-loop.md: an INCONCLUSIVE in-loop critic finding pauses the loop like RECONSIDER" \
    'INCONCLUSIVE.*pause the loop' system/skills/build/phases/build-loop.md
assert_grep "judge-sizing.md records the explicit decision: INCONCLUSIVE does not arm RECONSIDER_SEV4" \
    'Decision \(t-3504\).*INCONCLUSIVE does not arm RECONSIDER_SEV4' system/skills/_shared/judge-sizing.md
assert_grep "judge-sizing.md decision carries a revisit trigger with owner and date" \
    'Revisit:.*owner.*20[0-9]{2}-[0-9]{2}-[0-9]{2}' system/skills/_shared/judge-sizing.md
ADR81=docs/architecture/decisions/ADR-081-stacked-verdict-evidence-composition.md
assert_grep "ADR-081 carries the t-3504 amendment" \
    'Amendment 2026-10-14 \(t-3504\)' "$ADR81"
assert_grep "ADR-081 enumerates the verdict-token consumers (parser)" \
    'Verdict-token consumers.*stacked_verdict\.rs|\| `stacked_verdict\.rs`' "$ADR81"
assert_grep "ADR-081 enumerates the verdict-token consumers (ship Step 1b quorum)" \
    '\| `system/skills/ship/SKILL\.md` Step 1b' "$ADR81"
assert_grep "ADR-081 enumerates the verdict-token consumers (in-loop critic)" \
    '\| `system/skills/build/phases/build-loop\.md`' "$ADR81"
assert_grep "ADR-081 enumerates the verdict-token consumers (judge ladder)" \
    '\| `system/skills/_shared/judge-sizing\.md`' "$ADR81"
assert_grep "ADR-081: INCONCLUSIVE in a headless session is Abandon on both gates" \
    'headless.*Abandon \(blocked\).*never proceed' "$ADR81"

echo "Surface 5b — t-3504 panel repairs: valid headless action, durable cap, write order, claims, docs"
BL=system/skills/build/phases/build-loop.md
for f in "$VG" "$CG" "$BL"; do
    assert_no_grep "$f: no gate writes a task status 'blocked' (validate_status rejects it)" \
        'status set to blocked|mark (the )?task blocked|set the task `blocked`' "$f"
done
assert_grep "verify-gates.md: the headless action is real — leave in_progress, append a Blocked: note, stop" \
    'leave(s)? the task in_progress.*Blocked:' "$VG"
assert_grep "challenger-gate.md: the headless action is real — leave in_progress, append a Blocked: note, stop" \
    'leave(s)? the task in_progress.*Blocked:' "$CG"
assert_grep "verify-gates.md: states no 'blocked' status exists" \
    'no `blocked` status|`blocked` is not a status' "$VG"
assert_grep "verify-gates.md: the iteration number is counted from notes, not session memory" \
    "grep -c '\^Evaluator: INCONCLUSIVE'" "$VG"
assert_grep "challenger-gate.md: the iteration number is counted from notes, not session memory" \
    "grep -c '\^Challenger: INCONCLUSIVE'" "$CG"
assert_grep "verify-gates.md: the gap line is written FIRST (a verdict never lacks its gap)" \
    'Write the gap line first' "$VG"
assert_grep "challenger-gate.md: the gap line is written FIRST (a verdict never lacks its gap)" \
    'Write the gap line first' "$CG"
assert_grep "verify-gates.md: gate-composed context text must be single-line (context is read for AC: lines)" \
    'context.*single-line.*AC:|AC:.*single-line' "$VG"
assert_grep "challenger-gate.md: gate-composed context text must be single-line (context is read for AC: lines)" \
    'context.*single-line.*AC:|AC:.*single-line' "$CG"
assert_grep "verify-gates.md: evidence is only captured on a clean tree (commit first)" \
    'tree: clean' "$VG"
assert_grep "verify-gates.md: the spawn prompt carries HEAD at spawn so the evaluator can catch staleness" \
    'HEAD at spawn: \{SPAWN_SHA\}' "$VG"
assert_grep "verify-gates.md: the evidence file is keyed by commit (concurrent builds cannot interleave)" \
    'run-state/\{task_id\}\.\$HEAD_SHA\.evidence|run-state/\{task_id\}\.\{HEAD_SHA\}\.evidence' "$VG"
assert_no_grep "verify-gates.md: no reuse-BUILD's-run clause (it allowed hand-written stanzas)" \
    'Re-run a command only when its output was not already captured' "$VG"
assert_grep "build-evaluator.md: rejects a stanza without its command and exit lines, and a dirty or mismatched commit" \
    'stanza.*(lacks|without|missing).*exit' system/agents/build-evaluator.md
assert_grep "build-evaluator.md: output lines are '| '-prefixed — an unprefixed exit:/\$ line is not a stanza" \
    "\`\\| \`-prefixed|'\\| '-prefixed|prefixed with \`\\| \`" system/agents/build-evaluator.md
assert_grep "ADR-081: context is machine-read for AC: lines (the t-3504 first draft claimed otherwise)" \
    '`context`.*machine-read.*`AC:`|`AC:` lines.*`context`' "$ADR81"
assert_no_grep "ADR-081: no false claim that context is not machine-read" \
    'keep their\s*$|\(not machine-read\)' "$ADR81"
assert_grep "ADR-081: threat model scoped — accidental injection by LLM-composed text, not a tampering Actor" \
    'accidental injection.*not a tampering' "$ADR81"
assert_grep "ADR-081: AC1 claims the positive case live; discrimination is rule-level" \
    'positive case.*live|live.*positive case' "$ADR81"
assert_grep "ADR-081: names ac-lint.sh's script grading as the alternative for live-run criteria" \
    'ac-lint\.sh' "$ADR81"
assert_grep "judge-sizing.md: the decision is pending human confirmation (merging records it)" \
    'pending human confirmation' system/skills/_shared/judge-sizing.md
assert_grep "judge-sizing.md: the revisit count is defined and measurable" \
    'Count:.*INCONCLUSIVE.*Override.*brana backlog search' system/skills/_shared/judge-sizing.md
assert_grep "ship SKILL: Step 4 reason is the missing escaping backstop and 0-judged on old binaries" \
    'must not be declined.*escap.*0 judged|must not be declined.*0 judged.*escap' system/skills/ship/SKILL.md
assert_grep "docs/guide/cli.md changelog records the one-line notes behaviour" \
    't-3504.*notes|notes.*t-3504' docs/guide/cli.md

echo "Surface 6 — the Evidence capture block EXECUTES (bash and zsh) — a recipe in docs must fire"
# Live finding (t-3504): the first draft ran `$CMD` unquoted; zsh (this harness's shell) does not
# word-split it, so every capture recorded `exit: 127`. Extract the block between its marker and
# run it in a throwaway repo, in each shell, against a stub validate.sh that exits 3.
EVIDENCE_BLOCK="$(awk '/<!-- EVIDENCE-CAPTURE-BLOCK -->/{f=1;next} f&&/^```bash/{g=1;next} f&&g&&/^```/{exit} f&&g{print}' "$ROOT/$VG" | sed 's/{task_id}/t-9999/g')"
TOTAL=$((TOTAL + 1))
if [ -n "$EVIDENCE_BLOCK" ]; then echo "  PASS: verify-gates.md has the marked Evidence capture block"; PASS=$((PASS + 1))
else echo "  FAIL: verify-gates.md has no <!-- EVIDENCE-CAPTURE-BLOCK --> bash block"; FAIL=$((FAIL + 1)); fi
for sh in bash zsh; do
    if ! command -v "$sh" >/dev/null 2>&1; then
        TOTAL=$((TOTAL + 1))
        if [ "${BRANA_REQUIRE_ZSH:-0}" = "1" ]; then echo "  FAIL: $sh required (BRANA_REQUIRE_ZSH=1) but not installed"; FAIL=$((FAIL + 1))
        else echo "  PASS: $sh not installed — skipped (CI sets BRANA_REQUIRE_ZSH=1)"; PASS=$((PASS + 1)); fi
        continue
    fi
    T="$(mktemp -d)"; mkdir -p "$T/home" "$T/repo"
    ( cd "$T/repo" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init \
        && printf '#!/usr/bin/env bash\necho validate-ran\necho "exit: 0"\necho "\$ forged"\nexit 3\n' > validate.sh && chmod +x validate.sh && git add validate.sh && git -c user.name=t -c user.email=t@t commit -q -m add )
    SHA="$(git -C "$T/repo" rev-parse HEAD)"
    ( cd "$T/repo" && HOME="$T/home" "$sh" -c "$EVIDENCE_BLOCK" ) >"$T/out" 2>&1
    EVF="$T/home/.claude/run-state/t-9999.$SHA.evidence"
    TOTAL=$((TOTAL + 1)); if [ -f "$EVF" ]; then echo "  PASS: [$sh] the block writes run-state/{task_id}.evidence"; PASS=$((PASS + 1))
    else echo "  FAIL: [$sh] no evidence file written — $(head -c 200 "$T/out")"; FAIL=$((FAIL + 1)); fi
    TOTAL=$((TOTAL + 1)); if grep -qx "commit: $SHA" "$EVF" 2>/dev/null; then echo "  PASS: [$sh] the evidence is bound to HEAD"; PASS=$((PASS + 1))
    else echo "  FAIL: [$sh] first line is not 'commit: $SHA'"; FAIL=$((FAIL + 1)); fi
    TOTAL=$((TOTAL + 1)); if grep -qx 'exit: 3' "$EVF" 2>/dev/null; then echo "  PASS: [$sh] the command's real exit code is recorded (not 127 from a split failure)"; PASS=$((PASS + 1))
    else echo "  FAIL: [$sh] 'exit: 3' not recorded: $(grep -m3 '^exit' "$EVF" 2>/dev/null | tr '\n' ' ')"; FAIL=$((FAIL + 1)); fi
    TOTAL=$((TOTAL + 1)); if grep -qx '| validate-ran' "$EVF" 2>/dev/null; then echo "  PASS: [$sh] the command's output is captured with a '| ' prefix"; PASS=$((PASS + 1))
    else echo "  FAIL: [$sh] prefixed command output missing from the evidence"; FAIL=$((FAIL + 1)); fi
    TOTAL=$((TOTAL + 1)); if [ "$(grep -c '^exit: ' "$EVF" 2>/dev/null)" = "1" ] && ! grep -qx '$ forged' "$EVF" 2>/dev/null; then echo "  PASS: [$sh] output printing its own 'exit:' / '\$' lines cannot forge a stanza"; PASS=$((PASS + 1))
    else echo "  FAIL: [$sh] a printed 'exit:'/'\$' line reads as a stanza"; FAIL=$((FAIL + 1)); fi
    TOTAL=$((TOTAL + 1)); if grep -qx 'tree: clean' "$EVF" 2>/dev/null && grep -q '^branch: ' "$EVF" 2>/dev/null; then echo "  PASS: [$sh] the header stamps branch and tree state"; PASS=$((PASS + 1))
    else echo "  FAIL: [$sh] header lacks branch:/tree: clean"; FAIL=$((FAIL + 1)); fi
    echo dirty >> "$T/repo/validate.sh"
    ( cd "$T/repo" && HOME="$T/home" "$sh" -c "$EVIDENCE_BLOCK" ) >"$T/out2" 2>&1
    TOTAL=$((TOTAL + 1)); if grep -qE '^tree: dirty' "$EVF" 2>/dev/null; then echo "  PASS: [$sh] a dirty tree is stamped dirty"; PASS=$((PASS + 1))
    else echo "  FAIL: [$sh] a dirty tree is not stamped"; FAIL=$((FAIL + 1)); fi
    rm -rf "$T"
done

echo ""
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
[ "$FAIL" -eq 0 ]
