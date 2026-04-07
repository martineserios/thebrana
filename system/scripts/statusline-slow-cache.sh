#!/usr/bin/env bash
# statusline-slow-cache.sh — Scheduled job (5min) that writes slow-changing
# signals to a TSV cache file for statusline.sh.
#
# Signals: ruflo health, portfolio pulse, knowledge freshness.
# Statusline reads this file — never queries ruflo directly.
#
# Output: 6 tab-separated fields:
#   ruflo_count  ruflo_reindex_date  ruflo_stale  portfolio_pending  knowledge_days  timestamp
#
# Override paths via env vars (for testing):
#   BRANA_SLOW_CACHE_FILE  — output file (default: ~/.claude/statusline-slow-cache.tsv)
#   BRANA_RUFLO_DB         — ruflo memory.db path
#   BRANA_KNOWLEDGE_DIR    — brana-knowledge repo path
#   BRANA_PORTFOLIO_DIRS   — colon-separated project dirs to scan

set -euo pipefail

CACHE_FILE="${BRANA_SLOW_CACHE_FILE:-$HOME/.claude/statusline-slow-cache.tsv}"
RUFLO_DB="${BRANA_RUFLO_DB:-$HOME/.swarm/memory.db}"
KNOWLEDGE_DIR="${BRANA_KNOWLEDGE_DIR:-$HOME/enter_thebrana/brana-knowledge}"
PORTFOLIO_DIRS="${BRANA_PORTFOLIO_DIRS:-$HOME/enter_thebrana/thebrana:$HOME/enter_thebrana/clients/*:$HOME/enter_thebrana/ventures/*}"

# ── Ruflo health ─────────────────────────────────────────
RUFLO_COUNT=0
RUFLO_REINDEX_DATE="-"
RUFLO_STALE=0

if [ -f "$RUFLO_DB" ] && command -v sqlite3 &>/dev/null; then
    RUFLO_COUNT=$(sqlite3 "$RUFLO_DB" "SELECT COUNT(*) FROM memory_entries" 2>/dev/null || echo 0)

    # Last reindex: most recent entry with namespace 'knowledge'
    LAST_REINDEX=$(sqlite3 "$RUFLO_DB" \
        "SELECT date(MAX(created_at)) FROM memory_entries WHERE namespace='knowledge'" \
        2>/dev/null || echo "")
    [ -n "$LAST_REINDEX" ] && [ "$LAST_REINDEX" != "null" ] && RUFLO_REINDEX_DATE="$LAST_REINDEX"

    # Stale entries: knowledge entries older than 30 days
    RUFLO_STALE=$(sqlite3 "$RUFLO_DB" \
        "SELECT COUNT(*) FROM memory_entries WHERE namespace='knowledge' AND created_at < datetime('now', '-30 days')" \
        2>/dev/null || echo 0)
fi

# ── Portfolio pulse ──────────────────────────────────────
PORTFOLIO_PENDING=0

# Expand globs in PORTFOLIO_DIRS
IFS=':' read -ra RAW_DIRS <<< "$PORTFOLIO_DIRS"
EXPANDED_DIRS=()
for pattern in "${RAW_DIRS[@]}"; do
    # shellcheck disable=SC2086
    for dir in $pattern; do
        [ -d "$dir" ] && EXPANDED_DIRS+=("$dir")
    done
done

for dir in "${EXPANDED_DIRS[@]}"; do
    TASKS_FILE="$dir/.claude/tasks.json"
    [ -f "$TASKS_FILE" ] || continue
    COUNT=$(jq '[.tasks[] | select((.status == "pending" or .status == "in_progress") and (.type == "task" or .type == "subtask"))] | length' "$TASKS_FILE" 2>/dev/null || echo 0)
    PORTFOLIO_PENDING=$((PORTFOLIO_PENDING + COUNT))
done

# ── Knowledge freshness ─────────────────────────────────
KNOWLEDGE_DAYS=0

if [ -d "$KNOWLEDGE_DIR/.git" ]; then
    LAST_COMMIT=$(git -C "$KNOWLEDGE_DIR" log -1 --format="%ct" -- dimensions/ 2>/dev/null || echo "")
    if [ -n "$LAST_COMMIT" ]; then
        NOW=$(date +%s)
        KNOWLEDGE_DAYS=$(( (NOW - LAST_COMMIT) / 86400 ))
    fi
fi

# ── Write cache ──────────────────────────────────────────
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S)

mkdir -p "$(dirname "$CACHE_FILE")"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$RUFLO_COUNT" "$RUFLO_REINDEX_DATE" "$RUFLO_STALE" \
    "$PORTFOLIO_PENDING" "$KNOWLEDGE_DAYS" "$TIMESTAMP" \
    > "$CACHE_FILE"
