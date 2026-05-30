#!/usr/bin/env bash
# measure-gate-c.sh — Gate C: accept/skip rate
#
# Reads all session-state*.json files and counts how many sessions have
# extract_metrics or substantive accomplished/learnings fields populated.
# Sessions with populated fields = "accepted" (EXTRACT ran + user accepted result).
# Sessions without = "skipped".
#
# Output: JSON {"gate":"C","sessions_scanned":N,"sessions_with_metrics":M,"rate":R,"threshold":0.70}
# Usage: ./measure-gate-c.sh

SESSION_DIR="$HOME/.claude/projects/-home-martineserios-enter-thebrana-thebrana/memory"
THRESHOLD=0.70

if [ ! -d "$SESSION_DIR" ]; then
  if command -v jq &>/dev/null; then
    jq -n --arg gate "C" --argjson threshold "$THRESHOLD" \
      '{gate:$gate, status:"no_data", note:"session directory not found", threshold:$threshold}'
  else
    echo "gate=C status=no_data note=session_directory_not_found threshold=$THRESHOLD"
  fi
  exit 0
fi

# Collect all session-state files (current + any archived/dated variants)
mapfile -t SESSION_FILES < <(find "$SESSION_DIR" -maxdepth 1 -name "session-state*.json" 2>/dev/null | sort)

TOTAL=${#SESSION_FILES[@]}

if [ "$TOTAL" -eq 0 ]; then
  if command -v jq &>/dev/null; then
    jq -n --arg gate "C" --argjson threshold "$THRESHOLD" \
      '{gate:$gate, status:"no_data", note:"no session-state*.json files found", threshold:$threshold}'
  else
    echo "gate=C status=no_data note=no_session_state_files_found threshold=$THRESHOLD"
  fi
  exit 0
fi

# Count sessions with meaningful extract data
WITH_METRICS=$(python3 -c "
import json, os, sys

files = sys.argv[1:]
count = 0

for f in files:
  try:
    with open(f) as fh:
      d = json.load(fh)
  except Exception:
    continue

  # Primary: explicit extract_metrics field
  if 'extract_metrics' in d:
    count += 1
    continue

  # Proxy: accomplished or learnings with at least 1 item
  accomplished = d.get('accomplished', [])
  learnings = d.get('learnings', [])
  if len(accomplished) > 0 or len(learnings) > 0:
    count += 1
    continue

print(count)
" "${SESSION_FILES[@]}" 2>/dev/null || echo 0)

if command -v jq &>/dev/null; then
  RATE=$(echo "scale=4; $WITH_METRICS / $TOTAL" | bc 2>/dev/null || echo "null")

  jq -n \
    --arg gate "C" \
    --argjson total "$TOTAL" \
    --argjson with_metrics "$WITH_METRICS" \
    --arg rate "$RATE" \
    --argjson threshold "$THRESHOLD" \
    '{
      gate:$gate,
      sessions_scanned:$total,
      sessions_with_metrics:$with_metrics,
      rate:($rate|tonumber),
      threshold:$threshold,
      note:"sessions_with_metrics = sessions where extract_metrics OR accomplished/learnings populated"
    }'
else
  RATE=$(echo "scale=4; $WITH_METRICS / $TOTAL" | bc 2>/dev/null || echo "N/A")
  echo "gate=C sessions_scanned=$TOTAL sessions_with_metrics=$WITH_METRICS rate=$RATE threshold=$THRESHOLD"
fi
