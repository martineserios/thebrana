#!/usr/bin/env bash
# test-autonomous-runner.sh — Stage 1 (observe-only) behaviour for the autonomous runner (t-2140).
# Hermetic: injects a synthetic task fixture (RUNNER_TASKS_JSON), disables the claude plan
# step (RUNNER_PLAN=0), and asserts eligibility selection, bounds, and the observe invariant
# (zero mutations). No network, no real backlog, no claude call.
set -u

REPO="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(cd "$(dirname "$0")/../../.." && pwd)")"
RUNNER="$REPO/system/scripts/autonomous-runner.sh"

PASS=0; FAIL=0
ok(){ if eval "$2"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  ✗ $1"; fi; }

if [ ! -f "$RUNNER" ]; then echo "FAIL: runner not found at $RUNNER"; exit 1; fi

TMP="$(mktemp -d /tmp/runner-test-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
FIX="$TMP/tasks.json"
cat > "$FIX" <<'EOF'
[
 {"id":"t-9001","subject":"eligible one","status":"pending","execution":"autonomous","priority":"P2","blocked_by":[]},
 {"id":"t-9002","subject":"p0 auto","status":"pending","execution":"autonomous","priority":"P0","blocked_by":[]},
 {"id":"t-9003","subject":"blocked auto","status":"pending","execution":"autonomous","priority":"P2","blocked_by":["t-1"]},
 {"id":"t-9004","subject":"not auto","status":"pending","execution":"code","priority":"P2","blocked_by":[]},
 {"id":"t-9005","subject":"eligible two","status":"pending","execution":"autonomous","priority":"P3","blocked_by":[]}
]
EOF
FIX_SUM_BEFORE="$(md5sum "$FIX" | awk '{print $1}')"
LEDGER="$TMP/ledger.jsonl"

RUNNER_TASKS_JSON="$FIX" RUNNER_PLAN=0 RUNNER_LEDGER="$LEDGER" RUNNER_MAX_TASKS=5 \
  bash "$RUNNER" --observe >/dev/null 2>&1
RC=$?

decision(){ jq -r --arg id "$1" 'select(.id==$id)|.decision' "$LEDGER" 2>/dev/null; }
reason(){ jq -r --arg id "$1" 'select(.id==$id)|.reason' "$LEDGER" 2>/dev/null; }

echo "autonomous-runner Stage 1 (observe) tests"
ok "exit 0 on clean observe pass" '[ "$RC" = "0" ]'
ok "ledger produced" '[ -s "$LEDGER" ]'
ok "t-9001 eligible -> would-run" '[ "$(decision t-9001)" = "would-run" ]'
ok "t-9005 eligible -> would-run" '[ "$(decision t-9005)" = "would-run" ]'
ok "t-9002 P0 -> excluded:p0" '[ "$(decision t-9002)" = "excluded" ] && [[ "$(reason t-9002)" == *p0* ]]'
ok "t-9003 blocked -> excluded:blocked" '[ "$(decision t-9003)" = "excluded" ] && [[ "$(reason t-9003)" == *block* ]]'
ok "t-9004 non-autonomous -> excluded" '[ "$(decision t-9004)" = "excluded" ] && [[ "$(reason t-9004)" == *autonom* ]]'

# Observe invariant: no mutation decisions ever emitted, fixture untouched.
ok "no mutation decisions in ledger" '! jq -r .decision "$LEDGER" | grep -qE "^(done|completed|merged|parked)$"'
ok "task source unchanged (read-only)" '[ "$(md5sum "$FIX" | awk "{print \$1}")" = "$FIX_SUM_BEFORE" ]'

# Bounds: batch cap.
LEDGER2="$TMP/ledger2.jsonl"
RUNNER_TASKS_JSON="$FIX" RUNNER_PLAN=0 RUNNER_LEDGER="$LEDGER2" RUNNER_MAX_TASKS=1 \
  bash "$RUNNER" --observe >/dev/null 2>&1
RUNCOUNT="$(jq -r 'select(.decision=="would-run")|.id' "$LEDGER2" 2>/dev/null | wc -l | tr -d ' ')"
ok "RUNNER_MAX_TASKS=1 caps would-run at 1" '[ "$RUNCOUNT" = "1" ]'

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
