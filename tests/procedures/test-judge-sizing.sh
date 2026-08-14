#!/usr/bin/env bash
# Test: judge-sizing shared block (t-2895 / ADR-082) — the sizing valve's deterministic core.
#
# WHAT IS UNDER TEST. system/skills/_shared/judge-sizing.md carries the JUDGE-SIZING-BLOCK:
#   resolve_judge_rung()      — (effort, nature, criticality_hit, signals_csv) → 0|1|2
#   nature_class()            — (kind, file list) → code|procedure|docs, riskiest wins
#   blind_author_arms()       — (rung, ac_state, nature) → yes|no  (ADR-082 §5 precondition)
#   parse_sibling_verdict()   — challenger verdict text → yes|no|missing  (signal 4 source)
#   judge_area_weight()       — escaped-defect log area count in 30-day window (signal 5)
#   brief allowlists          — subset-only vs denied verbs (ADR-082 §4e AC)
#
# CONTRACT PROPERTIES (ADR-082 §2, challenge-hardened):
#   - TOTAL: every input resolves to exactly one rung; rung 0 is the residual floor.
#   - Signals only raise. Unknown signal name or empty signals table → exit 2 LOUD
#     (exit-contract-lint registry precedent — a broken valve must never silently
#     de-arm to rung 0 nor cost-explode to rung 2).
#   - The empty-table guard is a plain counter, never ${#ARR[@]} under set -u
#     (pattern_set-u-empty-assoc-array-fails-open).
#
# Run: bash tests/procedures/test-judge-sizing.sh

set -uo pipefail

PASS=0; FAIL=0; TOTAL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected [$expected], got [$actual]"; FAIL=$((FAIL + 1))
    fi
}

assert_exit() {
    local desc="$1" expected_code="$2" actual_code="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected_code" = "$actual_code" ]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected exit [$expected_code], got [$actual_code]"; FAIL=$((FAIL + 1))
    fi
}

REPO_ROOT=$(git rev-parse --show-toplevel)
SIZING_MD="$REPO_ROOT/system/skills/_shared/judge-sizing.md"
TMPDIR_T=$(mktemp -d)
trap 'rm -rf "$TMPDIR_T"' EXIT

if [ ! -f "$SIZING_MD" ]; then
    echo "ERROR: $SIZING_MD does not exist — the sizing authority block is missing"
    exit 1
fi

# Extract by NAMED MARKER, not position (t-2493 precedent).
sed -n '/<!-- JUDGE-SIZING-BLOCK -->/,/<!-- \/JUDGE-SIZING-BLOCK -->/p' "$SIZING_MD" \
| sed '1d;$d' \
| sed '/^```/d' > "$TMPDIR_T/sizing.sh"

if [ ! -s "$TMPDIR_T/sizing.sh" ]; then
    echo "ERROR: JUDGE-SIZING-BLOCK markers missing or empty in $SIZING_MD"
    exit 1
fi
if ! grep -q 'resolve_judge_rung' "$TMPDIR_T/sizing.sh"; then
    echo "ERROR: JUDGE-SIZING-BLOCK does not contain resolve_judge_rung() — markers drifted"
    exit 1
fi

source "$TMPDIR_T/sizing.sh"

echo "=== rung 0 is the residual floor (incl. the plain-S-code case, ADR-082 challenge W4) ==="
assert_eq "XS docs, no crit, no signals      -> 0" "0" "$(resolve_judge_rung XS docs 0 '')"
assert_eq "S procedure, no crit, no signals  -> 0" "0" "$(resolve_judge_rung S procedure 0 '')"
assert_eq "S code, NO crit, no signals       -> 0" "0" "$(resolve_judge_rung S code 0 '')"

echo "=== rung 1: effort >= M OR code+criticality ==="
assert_eq "M docs                            -> 1" "1" "$(resolve_judge_rung M docs 0 '')"
assert_eq "L code no crit                    -> 1" "1" "$(resolve_judge_rung L code 0 '')"
assert_eq "XL procedure                      -> 1" "1" "$(resolve_judge_rung XL procedure 0 '')"
assert_eq "S code WITH crit hit              -> 1" "1" "$(resolve_judge_rung S code 1 '')"
assert_eq "S docs with crit hit (not code)   -> 0" "0" "$(resolve_judge_rung S docs 1 '')"

echo "=== rung 2: any hard signal fires; signals only raise ==="
for sig in RECONSIDER_SEV4 PASS_WITH_GAPS CRITICAL_PATH SIBLING_VERDICT ESCAPED_DEFECT_AREA; do
    assert_eq "signal $sig on XS docs        -> 2" "2" "$(resolve_judge_rung XS docs 0 "$sig")"
done
assert_eq "two signals, same rung 2 (no stacking)" "2" "$(resolve_judge_rung M code 1 'RECONSIDER_SEV4,PASS_WITH_GAPS')"

echo "=== broken valve is LOUD: exit 2, never a silent rung ==="
resolve_judge_rung XS docs 0 'NOT_A_SIGNAL' >/dev/null 2>&1; assert_exit "unknown signal name -> exit 2" 2 $?
( JUDGE_SIGNALS_COUNT=0; resolve_judge_rung XS docs 0 '' >/dev/null 2>&1 ); assert_exit "empty signals table -> exit 2" 2 $?
resolve_judge_rung "" code 0 '' >/dev/null 2>&1; assert_exit "empty effort still resolves (exit 0, floor)" 0 $?

echo "=== totality: every effort x nature x crit combo (no signals) resolves to exactly one of 0|1 ==="
for e in XS S M L XL '' null; do
  for n in code procedure docs; do
    for c in 0 1; do
      out=$(resolve_judge_rung "$e" "$n" "$c" '') ; rc=$?
      TOTAL=$((TOTAL + 1))
      if [ $rc -eq 0 ] && { [ "$out" = "0" ] || [ "$out" = "1" ]; }; then
          PASS=$((PASS + 1))
      else
          echo "  FAIL: totality hole at effort=[$e] nature=[$n] crit=[$c] — got [$out] rc=$rc"
          FAIL=$((FAIL + 1))
      fi
    done
  done
done
echo "  (totality sweep: 42 combos folded into the counters above)"

echo "=== nature_class: riskiest wins (kind floor vs file classes) ==="
assert_eq "kind fix + only .md docs files    -> code (kind floor)" "code" "$(nature_class fix 'docs/notes.md')"
assert_eq "kind docs + a .rs file           -> code (file wins)"  "code" "$(nature_class docs 'src/a.rs docs/x.md')"
assert_eq "kind docs + skills .md           -> procedure"          "procedure" "$(nature_class docs 'system/skills/build/SKILL.md')"
assert_eq "kind docs + plain .md            -> docs"               "docs" "$(nature_class docs 'docs/guide/x.md')"
assert_eq "kind ops + plain .md             -> procedure (kind floor)" "procedure" "$(nature_class ops 'docs/x.md')"
assert_eq "kind null + hooks .sh            -> code"               "code" "$(nature_class null 'system/hooks/a.sh')"

echo "=== blind_author_arms: rung>=1 AND ac_state approved AND nature code (ADR-082 §5) ==="
assert_eq "rung1 approved code   -> yes" "yes" "$(blind_author_arms 1 approved code)"
assert_eq "rung2 approved code   -> yes" "yes" "$(blind_author_arms 2 approved code)"
assert_eq "rung0 approved code   -> no"  "no"  "$(blind_author_arms 0 approved code)"
assert_eq "rung1 none code       -> no"  "no"  "$(blind_author_arms 1 none code)"
assert_eq "rung1 proposed code   -> no"  "no"  "$(blind_author_arms 1 proposed code)"
assert_eq "rung1 approved docs   -> no (nature gate)" "no" "$(blind_author_arms 1 approved docs)"

echo "=== parse_sibling_verdict: recorded verdict field (signal 4 source) ==="
assert_eq "explicit yes"        "yes"     "$(parse_sibling_verdict 'Findings... SIBLINGS: yes — system/cli/rust/crates/x/src/other.rs')"
assert_eq "explicit no"         "no"      "$(parse_sibling_verdict 'All clear. SIBLINGS: no')"
assert_eq "field absent"        "missing" "$(parse_sibling_verdict 'PROCEED — no issues found.')"
assert_eq "case-insensitive"    "yes"     "$(parse_sibling_verdict 'siblings: YES — a.rs')"

echo "=== judge_area_weight: 30-day window + prefix match; absent file -> 0 ==="
LOG="$TMPDIR_T/escaped.jsonl"
recent=$(date +%Y-%m-%d)
old=$(date -d '45 days ago' +%Y-%m-%d)
cat > "$LOG" <<EOF
{"date":"$recent","area":"system/cli/rust/crates/brana-core","signal":"probe","rung_armed":2,"verified_findings":1,"cost_tokens":100}
{"date":"$recent","area":"system/hooks","signal":"probe","rung_armed":2,"verified_findings":1,"cost_tokens":100}
{"date":"$old","area":"system/cli/rust/crates/brana-core","signal":"probe","rung_armed":2,"verified_findings":1,"cost_tokens":100}
EOF
assert_eq "prefix match inside window"        "1" "$(judge_area_weight 'system/cli/rust' "$LOG")"
assert_eq "exact area inside window"          "1" "$(judge_area_weight 'system/hooks' "$LOG")"
assert_eq "no match"                          "0" "$(judge_area_weight 'docs/guide' "$LOG")"
assert_eq "absent file -> 0"                  "0" "$(judge_area_weight 'system/hooks' "$TMPDIR_T/nope.jsonl")"

echo "=== subset-only allowlists: no brief may carry a denied verb (ADR-082 §4e AC) ==="
TOTAL=$((TOTAL + 1))
if [ "${JUDGE_BRIEF_COUNT:-0}" -ge 4 ]; then
    echo "  PASS: brief library declares $JUDGE_BRIEF_COUNT briefs (>=4)"; PASS=$((PASS + 1))
else
    echo "  FAIL: brief library declares ${JUDGE_BRIEF_COUNT:-0} briefs — need >= 4"; FAIL=$((FAIL + 1))
fi
violations=$(judge_allowlist_violations)
assert_eq "allowlist ∩ denied-verbs = empty" "" "$violations"
TOTAL=$((TOTAL + 1))
if [ "${JUDGE_DENIED_COUNT:-0}" -ge 3 ]; then
    echo "  PASS: denied-verb list is non-trivial ($JUDGE_DENIED_COUNT entries)"; PASS=$((PASS + 1))
else
    echo "  FAIL: denied-verb list has ${JUDGE_DENIED_COUNT:-0} entries — suspiciously empty"; FAIL=$((FAIL + 1))
fi

echo "=== boundary: criticality_hit prefix semantics ==="
assert_eq "exact file match"            "1" "$(criticality_hit 'bootstrap.sh')"
assert_eq "subdir of critical prefix"   "1" "$(criticality_hit 'system/hooks/new-hook.sh')"
assert_eq "sibling non-critical path"   "0" "$(criticality_hit 'system/scripts/x.sh docs/a.md')"
assert_eq "prefix-substring is NOT a hit (system/hooks-extra)" "0" "$(criticality_hit 'system/hooks-extra/a.sh')"
assert_eq "empty file list"             "0" "$(criticality_hit '')"

echo "=== boundary: append_escaped_defect roundtrip (incl. control_arm) ==="
RLOG="$TMPDIR_T/roundtrip.jsonl"
append_escaped_defect "$RLOG" "system/hooks" "CRITICAL_PATH" 2 1 340000 '{"rung1_findings":1,"panel_findings":1}'
append_escaped_defect "$RLOG" "docs/guide" "RECONSIDER_SEV4" 2 0 120000
assert_eq "two records appended"        "2" "$(jq -s 'length' "$RLOG")"
assert_eq "control_arm preserved"       "1" "$(jq -s '.[0].control_arm.panel_findings' "$RLOG")"
assert_eq "no control_arm key when omitted" "null" "$(jq -s '.[1].control_arm' "$RLOG")"
assert_eq "roundtrip feeds area weight" "1" "$(judge_area_weight 'system/hooks' "$RLOG")"

echo ""
echo "=== Summary ==="
echo "Total: $TOTAL | Passed: $PASS | Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
