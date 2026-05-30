#!/usr/bin/env bash
# measure-gate-b.sh — Gate B: EXTRACT accuracy
#
# Compares what the EXTRACT step claimed (session-state accomplished/learnings)
# against what actually changed in the last commit (git diff HEAD~1 HEAD).
#
# Precision: of things EXTRACT mentioned → how many are in the actual diff?
# Recall: of things in the actual diff → how many did EXTRACT capture?
#
# Output: JSON {"gate":"B","precision":X,"recall":Y,"threshold":0.70}
# Usage: ./measure-gate-b.sh

GIT_ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || echo ".")
SESSION_DIR="$HOME/.claude/projects/-home-martineserios-enter-thebrana-thebrana/memory"
SESSION_FILE="$SESSION_DIR/session-state.json"

THRESHOLD=0.70

if [ ! -f "$SESSION_FILE" ]; then
  if command -v jq &>/dev/null; then
    jq -n --arg gate "B" --argjson threshold "$THRESHOLD" \
      '{gate:$gate, status:"no_data", note:"session-state.json not found", threshold:$threshold}'
  else
    echo "gate=B status=no_data note=session-state.json_not_found threshold=$THRESHOLD"
  fi
  exit 0
fi

# Check for extract_metrics field first (explicit)
HAS_EXTRACT=$(python3 -c "
import json, sys
try:
  d = json.load(open('$SESSION_FILE'))
  has = 'extract_metrics' in d
  print('true' if has else 'false')
except Exception as e:
  print('false')
" 2>/dev/null)

if [ "$HAS_EXTRACT" = "false" ]; then
  # Check for accomplished/learnings as proxy for EXTRACT output
  HAS_PROXY=$(python3 -c "
import json, sys
try:
  d = json.load(open('$SESSION_FILE'))
  accomplished = d.get('accomplished', [])
  learnings = d.get('learnings', [])
  has = (len(accomplished) + len(learnings)) > 0
  print('true' if has else 'false')
except Exception as e:
  print('false')
" 2>/dev/null)

  if [ "$HAS_PROXY" = "false" ]; then
    if command -v jq &>/dev/null; then
      jq -n --arg gate "B" --argjson threshold "$THRESHOLD" \
        '{gate:$gate, status:"no_data", note:"extract_metrics field not found in session state", threshold:$threshold}'
    else
      echo "gate=B status=no_data note=extract_metrics_field_not_found threshold=$THRESHOLD"
    fi
    exit 0
  fi
fi

# Get list of files actually changed in last commit
ACTUAL_FILES=$(git -C "$GIT_ROOT" diff --name-only HEAD~1 HEAD 2>/dev/null)
if [ -z "$ACTUAL_FILES" ]; then
  ACTUAL_FILES=$(git -C "$GIT_ROOT" show --name-only --format="" HEAD 2>/dev/null)
fi

ACTUAL_COUNT=$(echo "$ACTUAL_FILES" | grep -c . 2>/dev/null || echo 0)

if [ "$ACTUAL_COUNT" -eq 0 ]; then
  if command -v jq &>/dev/null; then
    jq -n --arg gate "B" --argjson threshold "$THRESHOLD" \
      '{gate:$gate, status:"no_data", note:"no files changed in last commit", threshold:$threshold}'
  else
    echo "gate=B status=no_data note=no_files_changed_in_last_commit threshold=$THRESHOLD"
  fi
  exit 0
fi

# Extract file mentions from accomplished + learnings fields
# Strategy: look for path-like strings (containing / or ending in known extensions)
EXTRACT_MENTIONS=$(python3 -c "
import json, re, sys

try:
  d = json.load(open('$SESSION_FILE'))
  items = d.get('accomplished', []) + d.get('learnings', [])
  text = ' '.join(str(i) for i in items)

  # Extract path-like tokens: contain / or end in common extensions
  tokens = re.findall(r'[\w\.\-/]+\.(?:rs|py|sh|md|json|ts|tsx|js|toml|yaml|yml)', text)
  tokens += re.findall(r'(?:system|docs|\.claude)/[\w\.\-/]+', text)

  # Deduplicate and normalize
  seen = set()
  out = []
  for t in tokens:
    t = t.strip('.,:;)')
    if t and t not in seen:
      seen.add(t)
      out.append(t)

  print('\n'.join(out))
except Exception as e:
  sys.stderr.write(str(e) + '\n')
  sys.exit(1)
" 2>/dev/null)

EXTRACT_COUNT=$(echo "$EXTRACT_MENTIONS" | grep -c . 2>/dev/null || echo 0)

if [ "$EXTRACT_COUNT" -eq 0 ]; then
  if command -v jq &>/dev/null; then
    jq -n --arg gate "B" --argjson threshold "$THRESHOLD" \
      '{gate:$gate, status:"no_data", note:"no file paths found in extract output (accomplished/learnings)", threshold:$threshold}'
  else
    echo "gate=B status=no_data note=no_file_paths_in_extract threshold=$THRESHOLD"
  fi
  exit 0
fi

# Calculate precision: extract mentions that appear in actual diff
PRECISION_HITS=0
while IFS= read -r mention; do
  [ -z "$mention" ] && continue
  # Check if any actual file path contains this mention (basename match)
  base=$(basename "$mention")
  if echo "$ACTUAL_FILES" | grep -qF "$base" || echo "$ACTUAL_FILES" | grep -qF "$mention"; then
    PRECISION_HITS=$((PRECISION_HITS + 1))
  fi
done <<< "$EXTRACT_MENTIONS"

# Calculate recall: actual files that are mentioned in extract
RECALL_HITS=0
while IFS= read -r actual_file; do
  [ -z "$actual_file" ] && continue
  base=$(basename "$actual_file")
  if echo "$EXTRACT_MENTIONS" | grep -qF "$base" || echo "$EXTRACT_MENTIONS" | grep -qF "$actual_file"; then
    RECALL_HITS=$((RECALL_HITS + 1))
  fi
done <<< "$ACTUAL_FILES"

if command -v jq &>/dev/null; then
  PRECISION=$(echo "scale=4; $PRECISION_HITS / $EXTRACT_COUNT" | bc 2>/dev/null || echo "null")
  RECALL=$(echo "scale=4; $RECALL_HITS / $ACTUAL_COUNT" | bc 2>/dev/null || echo "null")

  jq -n \
    --arg gate "B" \
    --argjson extract_count "$EXTRACT_COUNT" \
    --argjson actual_count "$ACTUAL_COUNT" \
    --argjson precision_hits "$PRECISION_HITS" \
    --argjson recall_hits "$RECALL_HITS" \
    --arg precision "$PRECISION" \
    --arg recall "$RECALL" \
    --argjson threshold "$THRESHOLD" \
    '{
      gate:$gate,
      extract_mentions:$extract_count,
      actual_files:$actual_count,
      precision_hits:$precision_hits,
      recall_hits:$recall_hits,
      precision:($precision|tonumber),
      recall:($recall|tonumber),
      threshold:$threshold,
      note:"precision=extract_mentioned_and_real recall=real_files_mentioned_in_extract"
    }'
else
  PRECISION=$(echo "scale=4; $PRECISION_HITS / $EXTRACT_COUNT" | bc 2>/dev/null || echo "N/A")
  RECALL=$(echo "scale=4; $RECALL_HITS / $ACTUAL_COUNT" | bc 2>/dev/null || echo "N/A")
  echo "gate=B extract_mentions=$EXTRACT_COUNT actual_files=$ACTUAL_COUNT precision=$PRECISION recall=$RECALL threshold=$THRESHOLD"
fi
