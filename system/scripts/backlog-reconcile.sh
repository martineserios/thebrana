#!/usr/bin/env bash
# backlog-reconcile.sh — Bulk triage for stale pending tasks (t-1765).
#
# Identifies pending tasks that are unlikely to be worked on:
#   - older than --age-days (default: 60)
#   - at priority P3 or unset
#   - in research/dx-tooling stub epics
#
# Modes:
#   --dry-run   Show what would be cancelled (default)
#   --execute   Actually cancel the tasks via brana CLI
#
# Optional filters:
#   --age-days N        Minimum age in days (default: 60)
#   --priority P3|P2    Target priority (default: P3)
#   --epic SLUG         Limit to one epic (repeatable)
#   --work-type TYPE    Filter by work_type (repeatable)
#   --git-refs          Check git log for task ID mentions (word-boundary safe)
#
# Exit: 0 = success, 1 = nothing to cancel, 2 = dependency missing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${BRANA_REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# ── Args ───────────────────────────────────────────────────
DRY_RUN=true
AGE_DAYS=60
PRIORITY="P3"
TARGET_EPICS=()
TARGET_WORK_TYPES=()
CHECK_GIT_REFS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)         DRY_RUN=true; shift ;;
        --execute)         DRY_RUN=false; shift ;;
        --age-days)        AGE_DAYS="$2"; shift 2 ;;
        --priority)        PRIORITY="$2"; shift 2 ;;
        --epic)            TARGET_EPICS+=("$2"); shift 2 ;;
        --work-type)       TARGET_WORK_TYPES+=("$2"); shift 2 ;;
        --git-refs)        CHECK_GIT_REFS=true; shift ;;
        -h|--help)
            cat <<EOF
Usage: backlog-reconcile.sh [--dry-run|--execute] [options]

  --dry-run        Show what would be cancelled (default)
  --execute        Actually cancel matched tasks
  --age-days N     Minimum task age in days (default: 60)
  --priority P     Target priority level (default: P3)
  --epic SLUG      Filter by epic (repeatable; default: all)
  --work-type T    Filter by work_type (repeatable; default: all)
  --git-refs       Show git log mentions for each candidate

Purpose: bulk-cancel P3 pending tasks that are clearly abandoned — age >60d,
no recent activity, low priority. Reduces noise in close-time reconciliation.
EOF
            exit 0 ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

# ── Pre-flight ──────────────────────────────────────────────
if ! command -v brana &>/dev/null; then
    echo "backlog-reconcile: brana CLI not found" >&2
    exit 2
fi
if ! command -v python3 &>/dev/null; then
    echo "backlog-reconcile: python3 not found" >&2
    exit 2
fi

# ── Temp workspace ──────────────────────────────────────────
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TASKS_FILE="$TMP_DIR/tasks.json"
GIT_FILE="$TMP_DIR/git.txt"
EPICS_FILE="$TMP_DIR/epics.txt"
WORK_TYPES_FILE="$TMP_DIR/work_types.txt"

echo "Fetching pending tasks..." >&2
brana backlog query --status pending 2>/dev/null > "$TASKS_FILE"

if [ "$CHECK_GIT_REFS" = true ]; then
    echo "Loading git log..." >&2
    git -C "$REPO_ROOT" log --format="%H %s" 2>/dev/null > "$GIT_FILE"
else
    touch "$GIT_FILE"
fi

# Write filter lists to files
printf '%s\n' "${TARGET_EPICS[@]:-}" > "$EPICS_FILE"
printf '%s\n' "${TARGET_WORK_TYPES[@]:-}" > "$WORK_TYPES_FILE"

# ── Stage 1: age/priority pre-filter (pure Python, no epic resolution yet —
# epic resolution is a per-task subprocess walk, so it only runs against the
# much smaller post-filter survivor set, not all pending tasks) ────────────
STAGE1_FILE="$TMP_DIR/stage1.json"
python3 - "$TASKS_FILE" "$AGE_DAYS" "$PRIORITY" <<'PYEOF' > "$STAGE1_FILE"
import sys, json
from datetime import date

tasks_file, age_arg, priority = sys.argv[1:]
age_cutoff = int(age_arg)

with open(tasks_file) as f:
    data = json.load(f)

today = date.today()

survivors = []
skipped_age = 0
skipped_pri = 0

for t in data:
    created = t.get('created')
    if not created:
        skipped_age += 1
        continue

    age_days = (today - date.fromisoformat(created)).days
    if age_days < age_cutoff:
        skipped_age += 1
        continue

    pri = t.get('priority')
    if priority == 'P3' and pri not in ('P3', None):
        skipped_pri += 1
        continue
    elif priority == 'P2' and pri not in ('P2', 'P3', None):
        skipped_pri += 1
        continue

    t['_age_days'] = age_days
    survivors.append(t)

print(json.dumps({
    'total_pending': len(data),
    'skipped_age': skipped_age,
    'skipped_priority': skipped_pri,
    'survivors': survivors,
}))
PYEOF

# ── Stage 2: resolve each survivor's epic via the canonical parent-chain
# walk (system/skills/_shared/epic-ancestor-walk.md, t-2765) — reuses the
# single source of truth for the walk instead of re-implementing it in
# Python a third time (the exact drift risk ADR-065's Consequences section
# warns about). Bash resolves per-task; Python only ever consumes the
# result. Per the shared doc's exit contract, a non-zero exit means the
# lookup itself broke — that task is excluded and counted, never silently
# treated as "no epic".
EPIC_WALK_MD="$SCRIPT_DIR/../skills/_shared/epic-ancestor-walk.md"
# shellcheck disable=SC1090
source <(sed -n '/<!-- EPIC-WALK-BLOCK -->/,/<!-- \/EPIC-WALK-BLOCK -->/p' "$EPIC_WALK_MD" | grep -v '^<!--' | grep -v '^```')

SURVIVOR_IDS=$(python3 -c "
import json
with open('$STAGE1_FILE') as f:
    print('\n'.join(t['id'] for t in json.load(f)['survivors']))
")

EPIC_MAP_FILE="$TMP_DIR/epic_map.json"
SKIPPED_LOOKUP_FILE="$TMP_DIR/skipped_epic_lookup.txt"
echo 0 > "$SKIPPED_LOOKUP_FILE"
{
    echo "{"
    first=true
    skipped_lookup_failed=0
    while IFS= read -r tid; do
        [ -z "$tid" ] && continue
        if slug=$(resolve_epic_ancestor "$tid"); then
            [ "$first" = true ] && first=false || echo ","
            printf '  "%s": %s' "$tid" "$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$slug")"
        else
            echo "⚠ epic lookup failed for $tid — excluding from candidates (never silently treated as \"no epic\")" >&2
            skipped_lookup_failed=$((skipped_lookup_failed + 1))
        fi
    done <<< "$SURVIVOR_IDS"
    echo ""
    echo "}"
    echo "$skipped_lookup_failed" > "$SKIPPED_LOOKUP_FILE"
} > "$EPIC_MAP_FILE"

# ── Stage 3: apply epic/work_type filters, build candidates + by_epic ──────
ANALYSIS_FILE="$TMP_DIR/analysis.json"
python3 - "$STAGE1_FILE" "$EPIC_MAP_FILE" "$GIT_FILE" "$EPICS_FILE" "$WORK_TYPES_FILE" \
    "$AGE_DAYS" "$CHECK_GIT_REFS" "$SKIPPED_LOOKUP_FILE" <<'PYEOF' > "$ANALYSIS_FILE"
import sys, json, re
from collections import defaultdict

stage1_file, epic_map_file, git_file, epics_file, wt_file, age_arg, check_git, skipped_lookup_file = sys.argv[1:]
age_cutoff = int(age_arg)
check_git = check_git == 'true'

with open(stage1_file) as f:
    stage1 = json.load(f)

with open(epic_map_file) as f:
    epic_map = json.load(f)

with open(git_file) as f:
    git_lines = [l.strip() for l in f if l.strip()]

with open(epics_file) as f:
    target_epics = [l.strip() for l in f if l.strip()]

with open(wt_file) as f:
    target_wt = [l.strip() for l in f if l.strip()]

with open(skipped_lookup_file) as f:
    skipped_epic_lookup_failed = int(f.read().strip() or 0)

candidates = []
skipped_epic = 0

for t in stage1['survivors']:
    tid = t['id']
    if tid not in epic_map:
        continue  # excluded by a failed epic lookup (stage 2), already counted

    epic = epic_map[tid]  # '' means resolved successfully to "no epic ancestor"

    if target_epics and epic not in target_epics:
        skipped_epic += 1
        continue

    if target_wt and t.get('work_type') not in target_wt:
        skipped_epic += 1
        continue

    git_mentions = []
    if check_git and git_lines:
        pattern = re.compile(rf'\b{re.escape(tid)}\b')
        git_mentions = [ln[41:100] for ln in git_lines if pattern.search(ln)]

    candidates.append({
        'id': tid,
        'age': t['_age_days'],
        'priority': t.get('priority'),
        'epic': epic,
        'work_type': t.get('work_type', ''),
        'subject': t.get('subject', ''),
        'git_mentions': git_mentions,
    })

by_epic = defaultdict(int)
for c in candidates:
    by_epic[c['epic'] or '(none)'] += 1

print(json.dumps({
    'total_pending': stage1['total_pending'],
    'age_cutoff': age_cutoff,
    'skipped_age': stage1['skipped_age'],
    'skipped_priority': stage1['skipped_priority'],
    'skipped_epic': skipped_epic,
    'skipped_epic_lookup_failed': skipped_epic_lookup_failed,
    'candidate_count': len(candidates),
    'by_epic': dict(by_epic),
    'candidates': candidates,
}))
PYEOF

# ── Render ──────────────────────────────────────────────────
python3 - "$ANALYSIS_FILE" "$DRY_RUN" "$CHECK_GIT_REFS" <<'PYEOF'
import sys, json
from collections import Counter

with open(sys.argv[1]) as f:
    a = json.load(f)
dry = sys.argv[2] == 'true'
check_git = sys.argv[3] == 'true'

print('=== backlog-reconcile ===')
print()
print(f'Total pending:    {a["total_pending"]}')
print(f'Age filter (>{a["age_cutoff"]}d): excluded {a["skipped_age"]}')
print(f'Priority filter:  excluded {a["skipped_priority"]}')
print(f'Epic/type filter: excluded {a["skipped_epic"]}')
if a.get('skipped_epic_lookup_failed'):
    print(f'Epic lookup failed: excluded {a["skipped_epic_lookup_failed"]} (not treated as "no epic" — see stderr)')
print(f'Candidates:       {a["candidate_count"]}')
print()

if a['candidate_count'] == 0:
    print('Nothing to cancel — all pending tasks pass the filters.')
    sys.exit(0)

print('By epic:')
for epic, count in sorted(a['by_epic'].items(), key=lambda x: -x[1]):
    print(f'  {epic}: {count}')
print()

if check_git:
    with_git = [c for c in a['candidates'] if c['git_mentions']]
    print(f'With git mentions: {len(with_git)}')
    for c in with_git[:10]:
        print(f'  {c["id"]} ({c["age"]}d) — {c["subject"][:60]}')
        for g in c['git_mentions'][:2]:
            print(f'    git: {g}')
    print()

action = 'Would cancel' if dry else 'Cancelling'
print(f'{action} {a["candidate_count"]} tasks...')
print()
print(f'Sample (first 15):')
for c in a['candidates'][:15]:
    print(f'  {c["id"]} ({c["age"]}d {c["priority"] or "?"} {c["epic"] or "?"}) — {c["subject"][:60]}')
if a['candidate_count'] > 15:
    print(f'  ... and {a["candidate_count"] - 15} more')
print()
if dry:
    print('Re-run with --execute to apply.')
PYEOF

# ── Execute ─────────────────────────────────────────────────
if [ "$DRY_RUN" = false ]; then
    IDS=$(python3 -c "
import sys, json
with open('$ANALYSIS_FILE') as f:
    a = json.load(f)
for c in a['candidates']:
    print(c['id'])
")

    COUNT=0
    FAILED=0
    while IFS= read -r tid; do
        [ -z "$tid" ] && continue
        if brana backlog set "$tid" status cancelled >/dev/null 2>&1; then
            COUNT=$((COUNT + 1))
        else
            echo "WARN: failed to cancel $tid" >&2
            FAILED=$((FAILED + 1))
        fi
    done <<< "$IDS"

    echo "Done — cancelled $COUNT tasks, $FAILED failures."
fi
