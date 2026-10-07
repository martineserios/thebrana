#!/usr/bin/env bash
# The patterns.md cap must be one number everywhere (t-3476, ADR-095 decision 9):
# validate.sh Check 31a prunes at _P_CAP in code; the always-loaded rule and the
# session-end-persist creation template must state the same cap (and warn-at).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1 — $2"; }
CAP=$(grep -oE '_P_CAP=[0-9]+' "$ROOT/validate.sh" | head -1 | cut -d= -f2)
WARN=$(grep -oE '_P_WARN=[0-9]+' "$ROOT/validate.sh" | head -1 | cut -d= -f2)
echo "patterns cap consistency (validate: cap=$CAP warn=$WARN)"
[ -n "$CAP" ] && ok "validate.sh defines _P_CAP" || bad "validate.sh defines _P_CAP" "not found"
[ -n "$WARN" ] && ok "validate.sh defines _P_WARN" || bad "validate.sh defines _P_WARN" "not found"
grep -q "patterns.md\` (cap $CAP)" "$ROOT/system/rules/self-improvement.md" && ok "rule states cap $CAP" || bad "rule states cap $CAP" "$(grep -n 'patterns.md' "$ROOT/system/rules/self-improvement.md")"
grep -q "cap: $CAP | warn-at: $WARN" "$ROOT/system/hooks/session-end-persist.sh" && ok "creation template states cap $CAP / warn-at $WARN" || bad "template" "$(grep -n 'Pattern Store' "$ROOT/system/hooks/session-end-persist.sh")"
echo; echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
