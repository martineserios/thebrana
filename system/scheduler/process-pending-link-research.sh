#!/usr/bin/env bash
# process-pending-link-research.sh — capped batch: run /brana:research over
# pending link-tagged research tasks (t-2306)
#
# Extraction (fetch, read, synthesize) needs real LLM reasoning — unlike the
# oracle-hub capture cron (personal/deploy/process-link-queue.sh), which is
# pure scripting. Capped hard: MAX_PER_RUN tasks, --depth quick (cheapest
# research tier) — link volume is expected to rise once capture friction
# drops, so this must not scale unboundedly with it.
#
# Known limitation: /brana:research's target forms are topic / doc-number /
# creator: / leads / registry — there's no direct "give it a URL" mode. A
# purpose-built `leads` mode (ruflo research-leads namespace) would fit
# better, but wiring that up means reworking the capture cron's queue
# mechanism too. For this personal-automation script, passing the URL
# directly as the topic argument is proportionate: topic-mode search
# reliably surfaces the exact page, and Phase 3 deep-dive fetches it.
# Revisit `leads` mode if this proves too imprecise in practice.
#
# Env overrides (tests): BRANA_BIN, CLAUDE_BIN, LINK_RESEARCH_MAX, LINK_RESEARCH_TIMEOUT.
#
# Usage: ./system/scheduler/process-pending-link-research.sh [--dry-run]

set -uo pipefail

BRANA="${BRANA_BIN:-brana}"
CLAUDE="${CLAUDE_BIN:-claude}"
MAX_PER_RUN="${LINK_RESEARCH_MAX:-5}"
TIMEOUT_SEC="${LINK_RESEARCH_TIMEOUT:-600}"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
  esac
done

log() { echo "[process-pending-link-research] $*"; }

TASKS_JSON="$("$BRANA" backlog query --tag link --status pending --output json 2>/dev/null || echo '[]')"
COUNT="$(echo "$TASKS_JSON" | jq 'length' 2>/dev/null || echo 0)"

if [ "$COUNT" -eq 0 ]; then
  log "no pending link tasks — nothing to do"
  exit 0
fi

BATCH="$(echo "$TASKS_JSON" | jq -c ".[0:$MAX_PER_RUN]")"
BATCH_COUNT="$(echo "$BATCH" | jq 'length')"
log "$COUNT pending, processing $BATCH_COUNT this run (cap: $MAX_PER_RUN)"

echo "$BATCH" | jq -c '.[]' | while IFS= read -r task; do
  ID="$(echo "$task" | jq -r '.id')"
  URL="$(echo "$task" | jq -r '.context' | grep -oP '(?<=URL: )\S+' | head -1 || true)"

  if [ -z "$URL" ]; then
    log "skip $ID — no URL found in context"
    continue
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] would research: $ID ($URL)"
    continue
  fi

  log "researching $ID: $URL"
  if ! timeout "$TIMEOUT_SEC" "$CLAUDE" -p "/brana:research $URL --depth quick" --output-format text >/dev/null 2>&1; then
    log "claude failed for $ID (skipping — will retry next run, task stays pending)"
    continue
  fi
  log "done: $ID"
done
