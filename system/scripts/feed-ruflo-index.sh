#!/usr/bin/env bash
# feed-ruflo-index.sh — Index new feed entries into ruflo memory_entries
#
# Reads new entries from ~/.claude/scheduler/feed-log.jsonl since last run,
# converts to mcp-index.mjs format, and stores to ruflo for semantic search.
# Entries become searchable at the next session start (HNSW rebuilt on ruflo restart).
#
# Watermark: ~/.claude/scheduler/state/feed-ruflo-watermark (line count)
# Key schema: knowledge:feed:{feed-name}:{title-slug}
# Namespace:  knowledge
#
# Usage: ./system/scripts/feed-ruflo-index.sh [--force] [--dry-run]
#   --force    Re-index all entries (ignores watermark)
#   --dry-run  Show what would be indexed, no writes

set -euo pipefail

# Ensure nvm-installed node/ruflo binaries are on PATH (non-interactive shells miss this)
for _nvm_bin in "$HOME"/.nvm/versions/node/*/bin; do
    [ -x "$_nvm_bin/node" ] && export PATH="$_nvm_bin:$PATH" && break
done

FEED_LOG="$HOME/.claude/scheduler/feed-log.jsonl"
WATERMARK="$HOME/.claude/scheduler/state/feed-ruflo-watermark"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCP_INDEXER="$SCRIPT_DIR/mcp-index.mjs"
TMP_SECTIONS=$(mktemp /tmp/feed-ruflo-sections-XXXXXX.jsonl)

trap 'rm -f "$TMP_SECTIONS"' EXIT

mkdir -p "$(dirname "$WATERMARK")"

# ── Args ──────────────────────────────────────────────────────────────────────

FORCE=0
DRY_RUN_FLAG=""
for arg in "$@"; do
    case "$arg" in
        --force)   FORCE=1 ;;
        --dry-run) DRY_RUN_FLAG="--dry-run" ;;
    esac
done

# ── Watermark ─────────────────────────────────────────────────────────────────

if [ ! -f "$FEED_LOG" ]; then
    echo "[feed-ruflo-index] No feed log at $FEED_LOG"
    exit 0
fi

TOTAL_LINES=$(wc -l < "$FEED_LOG")

if [ "$FORCE" = "1" ]; then
    START_LINE=1
else
    LAST=$(cat "$WATERMARK" 2>/dev/null | tr -d '[:space:]') || LAST=0
    START_LINE=$((LAST + 1))
fi

NEW_COUNT=$((TOTAL_LINES - START_LINE + 1))
[ "$NEW_COUNT" -le 0 ] && { echo "[feed-ruflo-index] No new entries since last run ($TOTAL_LINES total)"; exit 0; }

echo "[feed-ruflo-index] Converting $NEW_COUNT new entries (lines $START_LINE–$TOTAL_LINES)"

# ── Convert to mcp-index format ───────────────────────────────────────────────

sed -n "${START_LINE},${TOTAL_LINES}p" "$FEED_LOG" | jq -c '
  . as $e |
  ($e.feed) as $feed |
  (
    $e.title
    | gsub("[\\n\\r\\t]"; " ")
    | ascii_downcase
    | gsub("[^a-z0-9]+"; "-")
    | ltrimstr("-") | rtrimstr("-")
    | .[0:50]
  ) as $slug |
  ($e.published // $e.polled_at | split("T")[0]) as $date |
  {
    key: ("knowledge:feed:" + $feed + ":" + $slug),
    value: ($date + " — " + ($e.title | gsub("[\\n\\r]"; " ")) + " | " + $e.link),
    namespace: "knowledge",
    tags: ["type:feed", ("feed:" + $feed), "source:intelligence-feed"]
  }
' > "$TMP_SECTIONS"

SECTION_COUNT=$(wc -l < "$TMP_SECTIONS" | tr -d ' ')
echo "[feed-ruflo-index] $SECTION_COUNT sections ready for indexing"

# ── Index via mcp-index.mjs ───────────────────────────────────────────────────

if [ ! -f "$MCP_INDEXER" ]; then
    echo "[feed-ruflo-index] ERROR: mcp-index.mjs not found at $MCP_INDEXER"
    exit 1
fi

node "$MCP_INDEXER" $DRY_RUN_FLAG "$TMP_SECTIONS"

# ── Update watermark (only on success, not dry-run) ───────────────────────────

if [ -z "$DRY_RUN_FLAG" ]; then
    echo "$TOTAL_LINES" > "$WATERMARK"
    echo "[feed-ruflo-index] Watermark updated to line $TOTAL_LINES"
fi
