#!/usr/bin/env bash
# Tests for retire-when annotations (t-1945).
#
# Model-compensation artifacts carry a machine-greppable retirement
# condition so future audits are `grep -r "retire-when:" system/`,
# not a re-investigation (architecture review 2026-06-10 §3).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0; FAIL=0; TOTAL=0

check() {
    local desc="$1" ok="$2"
    TOTAL=$((TOTAL+1))
    if [ "$ok" = "0" ]; then PASS=$((PASS+1)); echo "  PASS: $desc"
    else FAIL=$((FAIL+1)); echo "  FAIL: $desc"; fi
}

echo "=== retire-when annotations (t-1945) ==="

# T1/T2 — the two model-compensation hooks carry the annotation
grep -q "retire-when: default model" "$REPO_ROOT/system/hooks/hallucination-detect.sh"; check "T1: hallucination-detect.sh annotated" $?
grep -q "retire-when: default model" "$REPO_ROOT/system/hooks/bash-output-compress.sh"; check "T2: bash-output-compress.sh annotated" $?

# T3 — the audit grep enumerates exactly the annotated artifact set
#
# Scoped to hooks/ and scripts/ rather than all of system/. The annotation is a
# source-code convention, but system/state/ holds generated data: a sync-state
# run writes patterns-export.json there, and it embeds pattern prose describing
# this very convention, which then counts as a third annotated artifact. That
# made this test fail purely on whether sync-state had run first — it passed on
# CI only because the glob happens to sort retire-when before sync-state.
FOUND=$(grep -rl "retire-when:" "$REPO_ROOT/system/hooks/" "$REPO_ROOT/system/scripts/" 2>/dev/null | sort | xargs -n1 basename 2>/dev/null)
EXPECTED="bash-output-compress.sh
hallucination-detect.sh"
[ "$FOUND" = "$EXPECTED" ]; check "T3: grep -r retire-when enumerates the full set" $?

# T4 — the convention is documented
grep -q "retire-when" "$REPO_ROOT/docs/architecture/hooks.md"; check "T4: convention documented in hooks.md" $?

echo ""; echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
