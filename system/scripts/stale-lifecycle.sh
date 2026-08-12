#!/usr/bin/env bash
# stale-lifecycle.sh — weekly stale-task lifecycle job (t-2774).
# Spec: docs/architecture/features/stale-task-lifecycle-policy.md
# ADR:  docs/architecture/decisions/ADR-078-stale-task-park-via-tag.md
#
# (a) Auto-park pending P2/P3 task/subtask items stale >90d: tags +parked.
#     Already-parked tasks are structurally excluded (mirrors stale_tasks()'s
#     classify()=="pending" filter — a parked task classifies as "parked",
#     never "pending", so it can never appear here twice).
# (b) Escalate stale P0/P1: no tag mutation, count-only, written to a status
#     file for session-start to read cheaply (no live query on every session).
# (c) Weekly intake-vs-drain report: created vs completed, trailing 7/30d.
# (d) Unpark: classify() already treats task.status as authoritative over the
#     parked tag for by_state bucketing (status:in_progress -> "active" wins
#     regardless of the tag), but the raw tag itself lingers on tasks.json
#     until something removes it. This pass strips +parked from any task
#     whose status is no longer "pending" — tag hygiene, not a correctness
#     fix (ADR-078's noted consequence).
# Every park/unpark action (or would-park/would-unpark, in --dry-run) is
# logged to a JSONL file.
#
# Env (fixture overrides, for tests — see test-stale-lifecycle.sh):
#   STALE_TASKS_JSON      pending task-source override (file path). Default: live query.
#   STALE_ALL_TASKS_JSON  all-tasks source override (file path). Default: live query.
#   STALE_TODAY           frozen "today" (YYYY-MM-DD). Default: real date.
#   STALE_LOG_FILE / STALE_STATUS_FILE / STALE_REPORT_FILE   output path overrides.
#   STALE_LIFECYCLE_PARK_DAYS       P2/P3 park threshold. Default: 90.
#   STALE_LIFECYCLE_ESCALATE_DAYS   P0/P1 escalation threshold. Default: 14.
#
# Usage:
#   stale-lifecycle.sh              # run for real (mutates tags, per (a))
#   stale-lifecycle.sh --dry-run    # report only, no tag mutations
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="$PROJECT_DIR/system/state"

LOG_FILE="${STALE_LOG_FILE:-$STATE_DIR/stale-lifecycle-log.jsonl}"
STATUS_FILE="${STALE_STATUS_FILE:-$STATE_DIR/stale-lifecycle-status.json}"
REPORT_FILE="${STALE_REPORT_FILE:-$STATE_DIR/stale-lifecycle-report.jsonl}"

PARK_DAYS="${STALE_LIFECYCLE_PARK_DAYS:-90}"
ESCALATE_DAYS="${STALE_LIFECYCLE_ESCALATE_DAYS:-14}"

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

TODAY="${STALE_TODAY:-$(date +%Y-%m-%d)}"
cutoff() { date -d "$TODAY - $1 days" +%Y-%m-%d; }

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$STATUS_FILE")" "$(dirname "$REPORT_FILE")"

# ── Data sources (fixture-overridable) ────────────────────────────────
if [ -n "${STALE_TASKS_JSON:-}" ]; then
    PENDING_JSON="$(cat "$STALE_TASKS_JSON" 2>/dev/null || echo '[]')"
else
    PENDING_JSON="$(brana backlog query --status pending --output json 2>/dev/null || echo '[]')"
fi

if [ -n "${STALE_ALL_TASKS_JSON:-}" ]; then
    ALL_JSON="$(cat "$STALE_ALL_TASKS_JSON" 2>/dev/null || echo '[]')"
else
    ALL_JSON="$(brana backlog query --output json 2>/dev/null || echo '[]')"
fi

# ── (a) Auto-park stale P2/P3 ─────────────────────────────────────────
PARK_CUTOFF="$(cutoff "$PARK_DAYS")"

TO_PARK="$(echo "$PENDING_JSON" | jq --arg cutoff "$PARK_CUTOFF" '
  [ .[] | select(
      (.type == "task" or .type == "subtask") and
      (.priority == "P2" or .priority == "P3") and
      (.created // "9999-99-99") < $cutoff and
      ((.tags // []) | index("parked") | not)
    ) | {id, priority, created} ]
')"

echo "$TO_PARK" | jq -c '.[]' | while IFS= read -r row; do
    [ -z "$row" ] && continue
    TID="$(echo "$row" | jq -r .id)"
    TPRI="$(echo "$row" | jq -r .priority)"
    TCREATED="$(echo "$row" | jq -r .created)"
    ACTION="would-park"
    if [ "$DRY_RUN" = false ]; then
        brana backlog set "$TID" tags "+parked" >/dev/null 2>&1 || true
        ACTION="park"
    fi
    jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg id "$TID" --arg action "$ACTION" \
        --arg reason "stale >${PARK_DAYS}d, priority $TPRI" --arg created "$TCREATED" \
        '{ts: $ts, task_id: $id, action: $action, reason: $reason, created: $created}' >> "$LOG_FILE"
done

# ── (b) Escalate stale P0/P1 (count-only, no tag mutation) ────────────
ESCALATE_CUTOFF="$(cutoff "$ESCALATE_DAYS")"

STALE_P0P1_COUNT="$(echo "$PENDING_JSON" | jq --arg cutoff "$ESCALATE_CUTOFF" '
  [ .[] | select(
      (.type == "task" or .type == "subtask") and
      (.priority == "P0" or .priority == "P1") and
      (.created // "9999-99-99") < $cutoff and
      ((.tags // []) | index("parked") | not)
    ) ] | length
')"

jq -nc --argjson count "$STALE_P0P1_COUNT" --arg updated "$TODAY" --argjson days "$ESCALATE_DAYS" \
    '{stale_p0p1_count: $count, threshold_days: $days, updated: $updated}' > "$STATUS_FILE"

# ── (c) Weekly intake-vs-drain report ──────────────────────────────────
C7="$(cutoff 7)"; C30="$(cutoff 30)"

REPORT_COUNTS="$(echo "$ALL_JSON" | jq --arg c7 "$C7" --arg c30 "$C30" '
  [ .[] | select(.type == "task" or .type == "subtask") ] as $tasks |
  {
    created_7d:   ([$tasks[] | select((.created // "") >= $c7)] | length),
    created_30d:  ([$tasks[] | select((.created // "") >= $c30)] | length),
    completed_7d: ([$tasks[] | select(.status == "completed" and (.completed // "") >= $c7)] | length),
    completed_30d:([$tasks[] | select(.status == "completed" and (.completed // "") >= $c30)] | length)
  }
')"

echo "$REPORT_COUNTS" | jq -c --arg date "$TODAY" '. + {date: $date}' >> "$REPORT_FILE"

# ── (d) Unpark: strip +parked from tasks no longer pending ────────────
TO_UNPARK="$(echo "$ALL_JSON" | jq '
  [ .[] | select(
      ((.tags // []) | index("parked")) and
      (.status != "pending")
    ) | {id, status} ]
')"

echo "$TO_UNPARK" | jq -c '.[]' | while IFS= read -r row; do
    [ -z "$row" ] && continue
    TID="$(echo "$row" | jq -r .id)"
    TSTATUS="$(echo "$row" | jq -r .status)"
    ACTION="would-unpark"
    if [ "$DRY_RUN" = false ]; then
        brana backlog set "$TID" tags "-parked" >/dev/null 2>&1 || true
        ACTION="unpark"
    fi
    jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg id "$TID" --arg action "$ACTION" \
        --arg reason "status now $TSTATUS, parked tag stale" \
        '{ts: $ts, task_id: $id, action: $action, reason: $reason}' >> "$LOG_FILE"
done

echo "[stale-lifecycle] parked/would-park: $(echo "$TO_PARK" | jq 'length') | unparked/would-unpark: $(echo "$TO_UNPARK" | jq 'length') | stale P0/P1: $STALE_P0P1_COUNT | dry_run=$DRY_RUN"
