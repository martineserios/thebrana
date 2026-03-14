#!/usr/bin/env bash
# second-phase-check.sh — Weekly check for time-gated second-phase tasks (ADR-021)
#
# Reads tasks.json for tasks tagged "second-phase" or with soak gates.
# When a trigger condition is met, sets priority to P2 and updates context.
# Runs via scheduler: Mon 09:10.
#
# Usage:
#   second-phase-check.sh                    # Check all second-phase triggers
#   second-phase-check.sh --dry-run          # Report without modifying tasks.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TASKS_FILE="$PROJECT_DIR/.claude/tasks.json"
TODAY=$(date +%Y-%m-%d)
DRY_RUN=false

[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

if [ ! -f "$TASKS_FILE" ]; then
    echo "ERROR: tasks.json not found at $TASKS_FILE" >&2
    exit 1
fi

echo "=== Second-Phase Trigger Check ($TODAY) ==="
echo ""

TRIGGERED=0
CHECKED=0

# Helper: days between two dates (YYYY-MM-DD)
days_between() {
    local d1 d2
    d1=$(date -d "$1" +%s 2>/dev/null) || return 1
    d2=$(date -d "$2" +%s 2>/dev/null) || return 1
    echo $(( (d2 - d1) / 86400 ))
}

# Helper: check if a task's dependency was completed N+ days ago
check_time_trigger() {
    local task_id="$1"
    local dep_id="$2"
    local required_days="$3"
    local description="$4"

    CHECKED=$((CHECKED + 1))

    # Find dependency completion date
    local dep_completed
    dep_completed=$(uv run python -c "
import json, sys
data = json.load(open('$TASKS_FILE'))
for t in data['tasks']:
    if t['id'] == '$dep_id':
        print(t.get('completed') or '')
        sys.exit(0)
print('')
" 2>/dev/null) || dep_completed=""

    if [ -z "$dep_completed" ]; then
        echo "  SKIP: $task_id — dependency $dep_id not yet completed"
        return
    fi

    local elapsed
    elapsed=$(days_between "$dep_completed" "$TODAY") || return

    if [ "$elapsed" -ge "$required_days" ]; then
        echo "  TRIGGERED: $task_id — $description ($elapsed days since $dep_id completed, threshold: $required_days)"
        TRIGGERED=$((TRIGGERED + 1))

        if ! $DRY_RUN; then
            uv run python -c "
import json
with open('$TASKS_FILE') as f:
    data = json.load(f)
for t in data['tasks']:
    if t['id'] == '$task_id':
        if t.get('priority') != 'P2' or 'Trigger fired' not in (t.get('context') or ''):
            t['priority'] = 'P2'
            ctx = t.get('context') or ''
            trigger_msg = '$TODAY: Trigger fired. $description ($elapsed days since $dep_id completed).'
            t['context'] = (ctx + '\n' + trigger_msg).strip() if ctx else trigger_msg
            print(f'Updated {t[\"id\"]}: priority=P2, context updated')
        else:
            print(f'{t[\"id\"]} already triggered')
        break
with open('$TASKS_FILE', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
" 2>/dev/null
        fi
    else
        local remaining=$((required_days - elapsed))
        echo "  WAIT: $task_id — $remaining days until trigger ($elapsed/$required_days days)"
    fi
}

# Helper: check soak gate (task blocked_by dependencies, with soak period)
check_soak_gate() {
    local task_id="$1"
    local soak_days="$2"
    local description="$3"

    CHECKED=$((CHECKED + 1))

    # Find the latest completion date among all blocked_by dependencies
    local latest_dep_completed
    latest_dep_completed=$(uv run python -c "
import json, sys
data = json.load(open('$TASKS_FILE'))
task = next((t for t in data['tasks'] if t['id'] == '$task_id'), None)
if not task:
    sys.exit(1)
blocked_by = task.get('blocked_by') or []
if not blocked_by:
    sys.exit(1)
dates = []
for t in data['tasks']:
    if t['id'] in blocked_by and t.get('completed'):
        dates.append(t['completed'])
if len(dates) == len(blocked_by):
    print(max(dates))
else:
    print('')
" 2>/dev/null) || latest_dep_completed=""

    if [ -z "$latest_dep_completed" ]; then
        echo "  SKIP: $task_id — not all dependencies completed yet"
        return
    fi

    local elapsed
    elapsed=$(days_between "$latest_dep_completed" "$TODAY") || return

    if [ "$elapsed" -ge "$soak_days" ]; then
        echo "  TRIGGERED: $task_id — $description ($elapsed days soak, threshold: $soak_days)"
        TRIGGERED=$((TRIGGERED + 1))

        if ! $DRY_RUN; then
            uv run python -c "
import json
with open('$TASKS_FILE') as f:
    data = json.load(f)
for t in data['tasks']:
    if t['id'] == '$task_id':
        if t.get('priority') != 'P2' or 'Trigger fired' not in (t.get('context') or ''):
            t['priority'] = 'P2'
            ctx = t.get('context') or ''
            trigger_msg = '$TODAY: Soak gate passed. $description ($elapsed days since dependencies completed).'
            t['context'] = (ctx + '\n' + trigger_msg).strip() if ctx else trigger_msg
            print(f'Updated {t[\"id\"]}: priority=P2, context updated')
        else:
            print(f'{t[\"id\"]} already triggered')
        break
with open('$TASKS_FILE', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
" 2>/dev/null
        fi
    else
        local remaining=$((soak_days - elapsed))
        echo "  WAIT: $task_id — $remaining days until soak gate passes ($elapsed/$soak_days days)"
    fi
}

# ── Registered triggers ──────────────────────────────────────────────

# t-455: Kill cascade commands — 14-day soak after phases 8+9
check_soak_gate "t-455" 14 "Kill cascade commands + archive doc 24"

# t-432 (now t-440): Ruflo precision eval — 90 days after Phase 5 (t-448)
check_time_trigger "t-440" "t-448" 90 "Evaluate ruflo retrieval precision@k"

# t-439: SemVerDoc + confidence tiers — 90 days after Phase 4 (t-447)
check_time_trigger "t-439" "t-447" 90 "Add SemVerDoc + confidence tiers"

# t-440 (now reassigned): Field notes lifecycle — 30 days after Phase 2 (t-445)
# Note: original t-432 was reassigned to t-440 during duplicate fix
check_time_trigger "t-440" "t-445" 30 "Expand field notes lifecycle (keep/archive → 5 actions)"

# t-441: Semantic drift detection — quarterly (90 days from last check)
check_time_trigger "t-441" "t-451" 90 "LLM-assisted semantic drift detection"

echo ""
echo "=== Summary ==="
echo "Checked:   $CHECKED triggers"
echo "Triggered: $TRIGGERED"
if $DRY_RUN; then
    echo "(dry run — no tasks.json changes)"
fi
