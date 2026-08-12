#!/usr/bin/env bash
# test-stale-lifecycle.sh — hermetic tests for stale-lifecycle.sh (t-2774/t-2781).
# Follows the RUNNER_TASKS_JSON fixture-override idiom from
# system/scripts/autonomous-runner.sh / test-autonomous-runner.sh: no live
# backlog, no network, no real tag mutations. Fixture dates are fixed
# relative to a frozen "today" (STALE_TODAY override) so the test is not
# time-dependent.
set -u

REPO="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(cd "$(dirname "$0")/../../.." && pwd)")"
SCRIPT="$REPO/system/scripts/stale-lifecycle.sh"

PASS=0; FAIL=0
ok(){ if eval "$2"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  ✗ $1"; fi; }

if [ ! -f "$SCRIPT" ]; then echo "FAIL: script not found at $SCRIPT"; exit 1; fi

TMP="$(mktemp -d /tmp/stale-lifecycle-test-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Frozen "today" — cutoffs computed against this, not the real date.
FROZEN_TODAY="2026-08-12"

# Pending fixture (feeds park + escalate): mix of priorities, staleness, and
# an already-parked task that must be excluded from both park and escalate
# (mirrors stale_tasks()'s classify()=="pending" exclusion — see ADR-078).
PENDING_FIX="$TMP/pending.json"
cat > "$PENDING_FIX" <<'EOF'
[
  {"id":"t-9101","type":"task","status":"pending","priority":"P2","created":"2026-04-01","tags":[]},
  {"id":"t-9102","type":"task","status":"pending","priority":"P3","created":"2026-08-01","tags":[]},
  {"id":"t-9103","type":"subtask","status":"pending","priority":"P2","created":"2026-01-01","tags":["parked"]},
  {"id":"t-9104","type":"task","status":"pending","priority":"P1","created":"2026-06-01","tags":[]},
  {"id":"t-9105","type":"task","status":"pending","priority":"P0","created":"2026-08-10","tags":[]},
  {"id":"t-9106","type":"task","status":"pending","priority":"P1","created":"2026-07-30","tags":[]},
  {"id":"t-9107","type":"phase","status":"pending","priority":"P2","created":"2026-01-01","tags":[]}
]
EOF

# All-tasks fixture (feeds the intake/drain report AND the unpark pass —
# tasks tagged "parked" whose status is no longer pending must be untagged,
# per ADR-078's consequence: classify() already treats status as authoritative
# over the tag for by_state bucketing, but the raw tag itself lingers unless
# something removes it — that's this job's cleanup pass).
# created/completed dates straddle the 7d/30d cutoffs from FROZEN_TODAY.
ALL_FIX="$TMP/all.json"
cat > "$ALL_FIX" <<'EOF'
[
  {"id":"t-9201","type":"task","status":"completed","priority":"P2","created":"2026-08-11","completed":"2026-08-11"},
  {"id":"t-9202","type":"task","status":"completed","priority":"P2","created":"2026-07-01","completed":"2026-07-20"},
  {"id":"t-9203","type":"task","status":"pending","priority":"P2","created":"2026-08-05"},
  {"id":"t-9204","type":"subtask","status":"pending","priority":"P3","created":"2026-06-01"},
  {"id":"t-9205","type":"phase","status":"completed","priority":"P2","created":"2026-08-05","completed":"2026-08-06"},
  {"id":"t-9206","type":"task","status":"in_progress","priority":"P2","created":"2026-06-01","tags":["parked"]},
  {"id":"t-9207","type":"task","status":"completed","priority":"P2","created":"2026-05-01","completed":"2026-08-01","tags":["parked"]},
  {"id":"t-9208","type":"task","status":"pending","priority":"P2","created":"2026-06-01","tags":["parked"]}
]
EOF

LOG="$TMP/log.jsonl"
STATUS="$TMP/status.json"
REPORT="$TMP/report.jsonl"

STALE_TODAY="$FROZEN_TODAY" \
STALE_TASKS_JSON="$PENDING_FIX" \
STALE_ALL_TASKS_JSON="$ALL_FIX" \
STALE_LOG_FILE="$LOG" \
STALE_STATUS_FILE="$STATUS" \
STALE_REPORT_FILE="$REPORT" \
  bash "$SCRIPT" --dry-run >/dev/null 2>&1
RC=$?

echo "stale-lifecycle.sh tests"
ok "exits 0" '[ "$RC" = "0" ]'

# ── Park selection (P2/P3, >90d stale, unparked) ──────────────────────
ok "log produced" '[ -s "$LOG" ]'
ok "t-9101 (P2, 133d stale, unparked) -> would-park" \
  'jq -e "select(.task_id==\"t-9101\" and .action==\"would-park\")" "$LOG" >/dev/null'
ok "t-9102 (P3, 11d, NOT stale) -> absent from log" \
  '! jq -e "select(.task_id==\"t-9102\")" "$LOG" >/dev/null'
ok "t-9103 (already parked) -> excluded from park log entirely" \
  '! jq -e "select(.task_id==\"t-9103\")" "$LOG" >/dev/null'
ok "t-9107 (type=phase, stale, P2) -> excluded (not task/subtask)" \
  '! jq -e "select(.task_id==\"t-9107\")" "$LOG" >/dev/null'
ok "dry-run mutates nothing (only would-park actions, never park)" \
  '! jq -e "select(.action==\"park\")" "$LOG" >/dev/null'

# ── Escalation (P0/P1, >14d stale by default threshold) ──────────────
ok "status file produced" '[ -s "$STATUS" ]'
ok "stale P0/P1 count is 1 (t-9104 only: t-9105 is 2d, t-9106 is 13d, neither stale)" \
  '[ "$(jq -r .stale_p0p1_count "$STATUS")" = "1" ]'
ok "escalate action also logged to the JSONL audit log (not status-file-only)" \
  'jq -e "select(.action==\"escalate\" and .count==1)" "$LOG" >/dev/null'

# ── Weekly intake/drain report ────────────────────────────────────────
ok "report produced" '[ -s "$REPORT" ]'
ok "created_7d counts t-9201,t-9203,t-9204? no — t-9204 created 2026-06-01 excluded; expect 2 (t-9201,t-9203)" \
  '[ "$(tail -1 "$REPORT" | jq -r .created_7d)" = "2" ]'
ok "completed_7d counts t-9201 only (t-9202 completed 2026-07-20, >7d)" \
  '[ "$(tail -1 "$REPORT" | jq -r .completed_7d)" = "1" ]'
ok "completed_30d counts t-9201+t-9202+t-9207, excludes phase-type t-9205" \
  '[ "$(tail -1 "$REPORT" | jq -r .completed_30d)" = "3" ]'

# ── Unpark pass (job-driven): parked tag on a no-longer-pending task ──
ok "t-9206 (parked, now in_progress) -> would-unpark" \
  'jq -e "select(.task_id==\"t-9206\" and .action==\"would-unpark\")" "$LOG" >/dev/null'
ok "t-9207 (parked, now completed) -> would-unpark" \
  'jq -e "select(.task_id==\"t-9207\" and .action==\"would-unpark\")" "$LOG" >/dev/null'
ok "t-9208 (parked, still pending) -> NOT unparked (still legitimately stale-parked)" \
  '! jq -e "select(.task_id==\"t-9208\")" "$LOG" >/dev/null'
ok "dry-run unpark mutates nothing (only would-unpark, never unpark)" \
  '! jq -e "select(.action==\"unpark\")" "$LOG" >/dev/null'

# ── Boundary: empty fixture — must not crash, must produce zero counts ──
EMPTY_FIX="$TMP/empty.json"
echo '[]' > "$EMPTY_FIX"
LOG2="$TMP/log2.jsonl"; STATUS2="$TMP/status2.json"; REPORT2="$TMP/report2.jsonl"
STALE_TODAY="$FROZEN_TODAY" STALE_TASKS_JSON="$EMPTY_FIX" STALE_ALL_TASKS_JSON="$EMPTY_FIX" \
STALE_LOG_FILE="$LOG2" STALE_STATUS_FILE="$STATUS2" STALE_REPORT_FILE="$REPORT2" \
  bash "$SCRIPT" --dry-run >/dev/null 2>&1
RC2=$?
ok "empty fixture: exits 0, no crash" '[ "$RC2" = "0" ]'
ok "empty fixture: stale_p0p1_count is 0" '[ "$(jq -r .stale_p0p1_count "$STATUS2")" = "0" ]'
ok "empty fixture: log file has no park lines" '[ ! -s "$LOG2" ]'

# ── Boundary: created exactly ON the cutoff date is NOT stale (strict <) ──
BOUNDARY_FIX="$TMP/boundary.json"
cat > "$BOUNDARY_FIX" <<'EOF'
[
  {"id":"t-9301","type":"task","status":"pending","priority":"P2","created":"2026-05-14","tags":[]}
]
EOF
LOG3="$TMP/log3.jsonl"; STATUS3="$TMP/status3.json"; REPORT3="$TMP/report3.jsonl"
STALE_TODAY="$FROZEN_TODAY" STALE_TASKS_JSON="$BOUNDARY_FIX" STALE_ALL_TASKS_JSON="$EMPTY_FIX" \
STALE_LOG_FILE="$LOG3" STALE_STATUS_FILE="$STATUS3" STALE_REPORT_FILE="$REPORT3" \
  bash "$SCRIPT" --dry-run >/dev/null 2>&1
ok "created exactly on 90d cutoff (2026-05-14) is NOT stale (strict <, matches stale_tasks())" \
  '[ ! -s "$LOG3" ] || ! jq -e "select(.task_id==\"t-9301\")" "$LOG3" >/dev/null'

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
