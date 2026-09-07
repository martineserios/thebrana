#!/usr/bin/env bash
# test-autonomous-runner-plan-timeout.sh — t-3318: RUNNER_PLAN_TIMEOUT must fail OPEN
# (would-run "plan inconclusive"), never hang or fail closed, when the planning dispatch
# outruns its budget. Proves the safety-net claim in plan_task()'s comment: a timed-out
# plan step degrades to would-run, which downstream verify_diff / NEEDSHUMAN self-report /
# human PR review still catch — a timeout here is a margin concern, not a correctness one.
# Filed after t-3315 routed this call through sandbox_claude(), which wraps bwrap setup +
# optional egress-proxy startup (up to ~5s poll) inside the same budget that used to time
# only the raw call, tightening the effective margin (t-3318).
#
# Hermetic: RUNNER_SANDBOX=0 (decision-logic only — containment itself is covered by
# test-autonomous-runner-observe-sandbox.sh); a slow stub `claude` that sleeps past a short
# RUNNER_PLAN_TIMEOUT.
set -u

REPO="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(cd "$(dirname "$0")/../../.." && pwd)")"
RUNNER="$REPO/system/scripts/autonomous-runner.sh"
[ -f "$RUNNER" ] || { echo "FAIL: runner not found at $RUNNER"; exit 1; }

PASS=0; FAIL=0
ok(){ if eval "$2"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  ✗ $1"; fi; }

TMP="$(mktemp -d /tmp/runner-plantimeout-test-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

STUB="$TMP/claude"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
cat >/dev/null
sleep 5
echo "AUTODOABLE: should never be seen — timed out first"
STUBEOF
chmod +x "$STUB"

FIX="$TMP/tasks.json"
cat > "$FIX" <<'EOF'
[{"id":"t-8101","subject":"Slow plan step","status":"pending","execution":"autonomous","priority":"P2","blocked_by":[],"description":"","context":"","ac_state":"none"}]
EOF
LEDGER="$TMP/ledger.jsonl"

START=$(date +%s)
RUNNER_TASKS_JSON="$FIX" RUNNER_PLAN=1 CLAUDE_BIN="$STUB" RUNNER_SANDBOX=0 \
  RUNNER_PLAN_TIMEOUT=1 RUNNER_LEDGER="$LEDGER" RUNNER_MAX_TASKS=5 \
  bash "$RUNNER" --observe >/dev/null 2>&1
RC=$?
ELAPSED=$(( $(date +%s) - START ))

decision(){ jq -r --arg id "$1" 'select(.id==$id)|.decision' "$LEDGER" 2>/dev/null; }
reason(){ jq -r --arg id "$1" 'select(.id==$id)|.reason' "$LEDGER" 2>/dev/null; }

echo "autonomous-runner plan-timeout fail-open tests (t-3318)"
ok "exit 0 despite a timed-out plan step (never hangs/fails closed)" '[ "$RC" = "0" ]'
ok "returns well before the stub's 5s sleep completes"              '[ "$ELAPSED" -lt 4 ]'
ok "t-8101: timed-out plan -> would-run (fail OPEN, not parked)"    '[ "$(decision t-8101)" = "would-run" ]'
ok "t-8101: reason names the inconclusive plan, not a stub verdict" '[[ "$(reason t-8101)" == *"plan inconclusive"* ]]'

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
