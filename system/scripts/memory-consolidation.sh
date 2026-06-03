#!/usr/bin/env bash
# memory-consolidation.sh — threshold-triggered memory consolidation
# Brana's equivalent of CC's autoDream / Kairos consolidation logic.
#
# Does NOT call lint-heal.sh — separate scope, separate schedule, no lock collision.
# lint-heal.sh: weekly deterministic L2 (dedup, contradiction, imputation)
# This script: threshold-triggered L3 (debrief-flag consumption, date normalization)
#
# Trigger (OR logic): fire when:
#   (now - last_consolidation_ts > 86400) OR (session_count_since_run >= 5)
#
# Usage:
#   memory-consolidation.sh                         — normal run
#   memory-consolidation.sh --dry-run               — check threshold only, exit 0 if would run
#   memory-consolidation.sh --normalize-only <file> — normalize dates in one file, exit
#   memory-consolidation.sh --state-file <path>     — override state file path
#   memory-consolidation.sh --flags-file <path>     — override debrief-flags file path
#   memory-consolidation.sh --memory-root <path>    — override memory root glob base

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
STATE_FILE="${MEMORY_CONSOLIDATE_STATE_FILE:-$HOME/.swarm/lint-heal-state.json}"
FLAGS_FILE="${MEMORY_CONSOLIDATE_FLAGS_FILE:-$HOME/.swarm/debrief-flags.jsonl}"
MEMORY_ROOT="${MEMORY_CONSOLIDATE_MEMORY_ROOT:-$HOME/.claude/projects}"
LOG_FILE="${MEMORY_CONSOLIDATE_LOG:-$HOME/.claude/memory/consolidation-log.md}"
ARCHIVE_BASE="${MEMORY_CONSOLIDATE_ARCHIVE:-$HOME/.claude/memory/archive}"

DRY_RUN=false
NORMALIZE_ONLY_FILE=""

# ── Arg parse ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)          DRY_RUN=true ;;
    --state-file)       STATE_FILE="$2"; shift ;;
    --flags-file)       FLAGS_FILE="$2"; shift ;;
    --memory-root)      MEMORY_ROOT="$2"; shift ;;
    --normalize-only)   NORMALIZE_ONLY_FILE="$2"; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
  shift
done

# ── Functions ─────────────────────────────────────────────────────────────────

log() { echo "[memory-consolidation] $*" >&2; }

read_state() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo '{"last_run_ts":0,"session_count_since_run":0,"last_run_date":"","last_consolidation_ts":0}'
    return
  fi
  python3 -c "
import json, sys
d = json.load(open('$STATE_FILE'))
d.setdefault('last_consolidation_ts', 0)
print(json.dumps(d))
"
}

threshold_met() {
  local state="$1"
  local now_ts; now_ts=$(date +%s)
  local last_ts; last_ts=$(echo "$state" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('last_consolidation_ts',0))")
  local session_count; session_count=$(echo "$state" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('session_count_since_run',0))")
  local elapsed=$(( now_ts - last_ts ))

  log "elapsed=${elapsed}s, sessions=${session_count}"

  # OR logic: time arm (>24h) OR session arm (>=5)
  [[ $elapsed -gt 86400 ]] || [[ $session_count -ge 5 ]]
}

consume_debrief_flags() {
  [[ -f "$FLAGS_FILE" ]] || { log "no debrief-flags file found — skipping"; return; }

  local today; today=$(date +%Y-%m-%d)
  local archive_dir="$ARCHIVE_BASE/$today"
  local tmp; tmp=$(mktemp)
  local acted=0

  while IFS= read -r line; do
    local acted_on; acted_on=$(echo "$line" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('acted_on','false'))")
    if [[ "$acted_on" == "True" || "$acted_on" == "true" ]]; then
      echo "$line" >> "$tmp"
      continue
    fi

    local filename; filename=$(echo "$line" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('file',''))")
    if [[ -z "$filename" ]]; then
      echo "$line" >> "$tmp"
      continue
    fi

    # Find the file under MEMORY_ROOT
    local found_path
    found_path=$(find "$MEMORY_ROOT" -name "$filename" 2>/dev/null | head -1)

    if [[ -n "$found_path" ]]; then
      mkdir -p "$archive_dir"
      mv "$found_path" "$archive_dir/$filename"
      log "archived: $filename → $archive_dir/"
      acted=$((acted+1))
    else
      log "flagged file not found (already archived?): $filename"
    fi

    # Mark acted_on=true
    echo "$line" | python3 -c "
import json,sys
d = json.loads(sys.stdin.read())
d['acted_on'] = True
print(json.dumps(d))
" >> "$tmp"
  done < "$FLAGS_FILE"

  mv "$tmp" "$FLAGS_FILE"
  log "debrief-flag consumption: $acted files archived"
}

normalize_frontmatter_dates() {
  local file="$1"
  [[ -f "$file" ]] || return

  local today; today=$(date +%Y-%m-%d)
  local yesterday; yesterday=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d 2>/dev/null || echo "")

  # Only normalize inside the YAML frontmatter block (between first --- and second ---)
  # Use Python for safe frontmatter-only substitution
  python3 - "$file" "$today" "$yesterday" << 'PYEOF'
import sys, re

path = sys.argv[1]
today = sys.argv[2]
yesterday = sys.argv[3]

with open(path) as f:
    content = f.read()

# Split into frontmatter + body
if not content.startswith('---'):
    sys.exit(0)  # no frontmatter

parts = content.split('---', 2)
if len(parts) < 3:
    sys.exit(0)  # malformed

_, fm, body = parts

# Relative date patterns to normalize in frontmatter values only
# Only match on lines that are YAML key: value pairs (not URLs, not code)
def normalize_fm(fm, today, yesterday):
    lines = fm.splitlines(keepends=True)
    result = []
    for line in lines:
        # Match YAML key: <relative-date-value> pattern
        m = re.match(r'^(\s*\w[\w-]*\s*:\s*)(.+)$', line.rstrip('\n'))
        if m:
            key_part, val = m.group(1), m.group(2).strip()
            # Only normalize if value looks like a bare relative phrase (no / or : or .)
            if re.fullmatch(r'(yesterday|today|last \w+day|this \w+day)', val, re.IGNORECASE):
                if val.lower() == 'yesterday' and yesterday:
                    val = yesterday
                elif val.lower() == 'today':
                    val = today
                line = key_part + val + '\n'
        result.append(line)
    return ''.join(result)

new_fm = normalize_fm(fm, today, yesterday)
if new_fm == fm:
    sys.exit(0)  # no changes

with open(path, 'w') as f:
    f.write('---' + new_fm + '---' + body)

print(f"normalized dates in {path}", file=sys.stderr)
PYEOF
}

update_state() {
  local state="$1"
  local now_ts; now_ts=$(date +%s)
  local tmp; tmp=$(mktemp)

  echo "$state" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
d['last_consolidation_ts'] = $now_ts
print(json.dumps(d, indent=2))
" > "$tmp"

  # Atomic write
  mkdir -p "$(dirname "$STATE_FILE")"
  mv "$tmp" "$STATE_FILE"
}

append_log() {
  local files_changed="$1"
  local timestamp; timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "- $timestamp: consolidation run — $files_changed debrief flags consumed" >> "$LOG_FILE"
}

# ── Main ──────────────────────────────────────────────────────────────────────

# Normalize-only mode (must be after function definitions)
if [[ -n "$NORMALIZE_ONLY_FILE" ]]; then
  normalize_frontmatter_dates "$NORMALIZE_ONLY_FILE"
  exit 0
fi

STATE=$(read_state)

if ! threshold_met "$STATE"; then
  log "threshold not met — skipping"
  exit 1  # non-zero = skip (callers can ignore)
fi

log "threshold met — running consolidation"

if $DRY_RUN; then
  log "dry-run: would run consolidation (threshold met)"
  exit 0
fi

# Step 1: consume debrief flags
consume_debrief_flags
FLAGS_CONSUMED=$(grep -c '"acted_on": true\|"acted_on":true' "$FLAGS_FILE" 2>/dev/null || echo 0)

# Step 2: date normalization — frontmatter only
NORMALIZED=0
while IFS= read -r -d '' mf; do
  if normalize_frontmatter_dates "$mf"; then
    NORMALIZED=$((NORMALIZED+1))
  fi
done < <(find "$MEMORY_ROOT" -name "*.md" -print0 2>/dev/null)

log "date normalization: $NORMALIZED files processed"

# Step 3: write log
append_log "$FLAGS_CONSUMED"

# Step 4: update state (last_consolidation_ts = now)
update_state "$STATE"

log "consolidation complete"
