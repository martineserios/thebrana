#!/usr/bin/env bash
# feed-index.sh — Intelligence digest from brana feed log
#
# Reads new entries from ~/.claude/scheduler/feed-log.jsonl since last run,
# groups by feed, and writes a digest to ~/.claude/intelligence-feed-digest.md.
# Session-start surfaces the digest when it exists.
#
# Watermark: ~/.claude/scheduler/state/feed-index-watermark (line count)
# Output:    ~/.claude/intelligence-feed-digest.md
#
# Usage: ./system/scripts/feed-index.sh [--force]
#   --force  Re-index all entries (ignores watermark)

set -euo pipefail

FEED_LOG="$HOME/.claude/scheduler/feed-log.jsonl"
WATERMARK="$HOME/.claude/scheduler/state/feed-index-watermark"
DIGEST="$HOME/.claude/intelligence-feed-digest.md"
TMP_ENTRIES=$(mktemp)

trap 'rm -f "$TMP_ENTRIES"' EXIT

mkdir -p "$(dirname "$WATERMARK")"

# ── Watermark ─────────────────────────────────────────────────────────────────

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

if [ ! -f "$FEED_LOG" ]; then
    echo "[feed-index] No feed log found at $FEED_LOG — run 'brana feed poll --all' first"
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
[ "$NEW_COUNT" -le 0 ] && { echo "[feed-index] No new entries since last run ($TOTAL_LINES total)"; exit 0; }

# ── Extract new entries ───────────────────────────────────────────────────────

sed -n "${START_LINE},${TOTAL_LINES}p" "$FEED_LOG" > "$TMP_ENTRIES"

# Skip malformed JSON lines so jq calls below don't abort under set -e
TMP_VALID=$(mktemp)
while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "$line" | jq . >/dev/null 2>&1 && echo "$line" >> "$TMP_VALID" || true
done < "$TMP_ENTRIES"
mv "$TMP_VALID" "$TMP_ENTRIES"

ENTRY_COUNT=$(wc -l < "$TMP_ENTRIES" | tr -d ' ')
[ "$ENTRY_COUNT" -eq 0 ] && { echo "[feed-index] No valid JSON entries after filtering"; exit 0; }

echo "[feed-index] Processing $ENTRY_COUNT new entries (lines $START_LINE–$TOTAL_LINES)"

# ── Build digest ──────────────────────────────────────────────────────────────

DIGEST_DATE=$(date +%Y-%m-%d)
DIGEST_TIME=$(date +%H:%M)

# Get distinct feeds in this batch
FEEDS=$(jq -r '.feed' "$TMP_ENTRIES" | sort -u)

{
    echo "# Intelligence Feed Digest — $DIGEST_DATE"
    echo ""
    echo "> $ENTRY_COUNT new entries across $(echo "$FEEDS" | wc -l | tr -d ' ') feeds. Generated $DIGEST_TIME."
    echo "> Delete this file when reviewed: \`rm ~/.claude/intelligence-feed-digest.md\`"
    echo ""

    while IFS= read -r feed; do
        # Count entries for this feed
        FEED_COUNT=$(jq -r "select(.feed == \"$feed\")" "$TMP_ENTRIES" | jq -rs 'length')
        echo "## $feed ($FEED_COUNT)"
        echo ""

        # Print entries (most recent first, max 20 per feed)
        jq -r "select(.feed == \"$feed\") | \"\(.published // .polled_at | split(\"T\")[0]) — [\(.title | gsub(\"[\\n\\r]\"; \" \"))](\(.link))\"" \
            "$TMP_ENTRIES" | tail -20

        echo ""
    done <<< "$FEEDS"
} > "$DIGEST"

echo "$TOTAL_LINES" > "$WATERMARK"
echo "[feed-index] Digest written to $DIGEST ($ENTRY_COUNT entries)"
