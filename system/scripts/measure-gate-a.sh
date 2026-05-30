#!/usr/bin/env bash
# measure-gate-a.sh — Gate A: doc-update rate
#
# Counts behavioral commits (touching system/) in the last N days,
# and what fraction of those also touch docs/ or *.md files.
#
# Output: JSON  {"gate":"A","period_days":N,"behavioral_commits":X,"with_doc_updates":Y,"rate":Z,"threshold":0.80}
# Usage: ./measure-gate-a.sh [--days N]

GIT_ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || echo ".")

DAYS=30
while [[ $# -gt 0 ]]; do
  case "$1" in
    --days) DAYS="$2"; shift 2 ;;
    *) shift ;;
  esac
done

SINCE="$DAYS days ago"

# Get all commit hashes in the period on main
mapfile -t COMMITS < <(git -C "$GIT_ROOT" log --format="%H" --since="$SINCE" main 2>/dev/null)

BEHAVIORAL=0
WITH_DOCS=0

for SHA in "${COMMITS[@]}"; do
  # Get list of changed files for this commit
  FILES=$(git -C "$GIT_ROOT" show --name-only --format="" "$SHA" 2>/dev/null)

  # Behavioral = touches system/ (skills, hooks, rules, agents, procedures)
  if echo "$FILES" | grep -q '^system/'; then
    BEHAVIORAL=$((BEHAVIORAL + 1))
    # Doc update = also touches docs/ or any .md file
    if echo "$FILES" | grep -qE '(^docs/|\.md$)'; then
      WITH_DOCS=$((WITH_DOCS + 1))
    fi
  fi
done

THRESHOLD=0.80

if command -v jq &>/dev/null; then
  if [ "$BEHAVIORAL" -eq 0 ]; then
    RATE="null"
    NOTE='"note":"no behavioral commits in period"'
  else
    RATE=$(echo "scale=4; $WITH_DOCS / $BEHAVIORAL" | bc 2>/dev/null || echo "null")
    NOTE=""
  fi

  if [ -n "$NOTE" ]; then
    jq -n \
      --arg gate "A" \
      --argjson period "$DAYS" \
      --argjson behavioral "$BEHAVIORAL" \
      --argjson with_docs "$WITH_DOCS" \
      --argjson threshold "$THRESHOLD" \
      '{gate:$gate, period_days:$period, behavioral_commits:$behavioral, with_doc_updates:$with_docs, rate:null, threshold:$threshold, note:"no behavioral commits in period"}'
  else
    jq -n \
      --arg gate "A" \
      --argjson period "$DAYS" \
      --argjson behavioral "$BEHAVIORAL" \
      --argjson with_docs "$WITH_DOCS" \
      --arg rate "$RATE" \
      --argjson threshold "$THRESHOLD" \
      '{gate:$gate, period_days:$period, behavioral_commits:$behavioral, with_doc_updates:$with_docs, rate:($rate|tonumber), threshold:$threshold}'
  fi
else
  # Plain text fallback
  if [ "$BEHAVIORAL" -eq 0 ]; then
    RATE="N/A"
  else
    RATE=$(echo "scale=4; $WITH_DOCS / $BEHAVIORAL" | bc 2>/dev/null || echo "N/A")
  fi
  echo "gate=A period_days=$DAYS behavioral_commits=$BEHAVIORAL with_doc_updates=$WITH_DOCS rate=$RATE threshold=$THRESHOLD"
fi
