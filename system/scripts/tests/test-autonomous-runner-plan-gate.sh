#!/usr/bin/env bash
# test-autonomous-runner-plan-gate.sh — t-3315: plan_task() must judge on the task's actual
# description/context, not the subject alone, and must skip the LLM call entirely when
# ac_state is approved (ADR-079: the human's approval already is the judgment).
# Hermetic: stub `claude` echoes whether the DECISION_MARKER it looks for reached the prompt
# — that only happens if plan_task actually forwards description/context, not just subject.
# No network, no real backlog, no real claude call.
set -u

REPO="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(cd "$(dirname "$0")/../../.." && pwd)")"
RUNNER="$REPO/system/scripts/autonomous-runner.sh"

PASS=0; FAIL=0
ok(){ if eval "$2"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  ✗ $1"; fi; }

if [ ! -f "$RUNNER" ]; then echo "FAIL: runner not found at $RUNNER"; exit 1; fi

TMP="$(mktemp -d /tmp/runner-plangate-test-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# ── Stub claude: proves whether description/context reached the planning prompt ──
STUB="$TMP/claude"
CALL_LOG="$TMP/calls.log"
: > "$CALL_LOG"
cat > "$STUB" <<STUBEOF
#!/usr/bin/env bash
prompt="\$(cat)"
echo 1 >> "$CALL_LOG"
if printf '%s' "\$prompt" | grep -q "DECISION_MARKER_PRESENT"; then
  echo "AUTODOABLE: decisions found in description"
else
  echo "NEEDSHUMAN: no decisions found, subject alone is ambiguous"
fi
STUBEOF
chmod +x "$STUB"

FIX="$TMP/tasks.json"
cat > "$FIX" <<'EOF'
[
 {"id":"t-8001","subject":"Handle the tricky rotation","status":"pending","execution":"autonomous","priority":"P2","blocked_by":[],"description":"Rotate the widget clockwise by 90 degrees using the existing rotate() helper. DECISION_MARKER_PRESENT: use rotate(), no new interfaces.","context":"","ac_state":"none"},
 {"id":"t-8002","subject":"Handle the ambiguous case","status":"pending","execution":"autonomous","priority":"P2","blocked_by":[],"description":"","context":"","ac_state":"none"},
 {"id":"t-8003","subject":"Approved task with no decisions stated","status":"pending","execution":"autonomous","priority":"P2","blocked_by":[],"description":"","context":"","ac_state":"approved"}
]
EOF
LEDGER="$TMP/ledger.jsonl"

RUNNER_TASKS_JSON="$FIX" RUNNER_PLAN=1 CLAUDE_BIN="$STUB" RUNNER_LEDGER="$LEDGER" RUNNER_MAX_TASKS=5 \
  bash "$RUNNER" --observe >/dev/null 2>&1
RC=$?

decision(){ jq -r --arg id "$1" 'select(.id==$id)|.decision' "$LEDGER" 2>/dev/null; }
reason(){ jq -r --arg id "$1" 'select(.id==$id)|.reason' "$LEDGER" 2>/dev/null; }

echo "autonomous-runner plan-gate tests (t-3315)"
ok "exit 0 on clean observe pass" '[ "$RC" = "0" ]'
ok "t-8001: decisions stated in description -> would-run (not parked on subject alone)" \
  '[ "$(decision t-8001)" = "would-run" ]'
ok "t-8001: reason reflects the description reaching the prompt" \
  '[[ "$(reason t-8001)" == *"decisions found"* ]]'
ok "t-8002: no decisions anywhere -> still would-park (gate not broken open)" \
  '[ "$(decision t-8002)" = "would-park" ]'
ok "t-8003: ac_state approved -> would-run regardless of stub verdict" \
  '[ "$(decision t-8003)" = "would-run" ]'
ok "t-8003: reason names the approval, not a stub verdict" \
  '[[ "$(reason t-8003)" == *approved* ]]'
ok "t-8003: approved task never called claude (gate skipped before dispatch)" \
  '[ "$(wc -l < "$CALL_LOG" | tr -d " ")" = "2" ]'

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
