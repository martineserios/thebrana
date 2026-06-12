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
SUMMARIES="$HOME/.claude/scheduler/feed-summaries.jsonl"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORMAT_ENRICHED="$SCRIPT_DIR/feed-format-enriched.py"

TMP_ENTRIES=$(mktemp)
TMP_STALE=$(mktemp)

trap 'rm -f "$TMP_ENTRIES" "$TMP_STALE"' EXIT

# Feeds with full content in the entry (cc-changelog: summary field; claude-code-releases: content field)
# and feeds needing pre-generated summaries (anthropic-news: feed-summaries.jsonl)
HIGH_SIGNAL_FEEDS="cc-changelog claude-code-releases anthropic-news kapso-changelog"

# ── Staleness config (t-2001, ADR-055) ───────────────────────────────────────
FEEDS_JSON="$HOME/.claude/scheduler/feeds.json"
DEFAULT_STALE_DAYS=14
# Scraper-fed sources that are NOT registered in feeds.json (name:threshold_days).
# These only flag when entries exist and went stale — no "no entries yet" notice,
# so an undeployed scraper doesn't nag every digest.
EXTRA_STALE_FEEDS="kapso-changelog:21"

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

# ── Staleness pass (t-2001) ───────────────────────────────────────────────────
# Unconditional: runs even when there are no new entries (a stalled feed is
# precisely the no-new-entries case). Scans the FULL feed-log.jsonl — this read
# is intentionally not watermark-gated; the watermark contract is untouched.
# GNU `date -d` (Linux/systemd only — do not port to BSD `date -j`).

NOW_EPOCH=$(date +%s)

stale_universe() {
    # Emits "name:threshold:zero_notice" — zero_notice=1 only for registered feeds
    if [ -f "$FEEDS_JSON" ]; then
        jq -r --argjson d "$DEFAULT_STALE_DAYS" \
            '.[] | select(.enabled) | "\(.name):\(.stale_after_days // $d):1"' \
            "$FEEDS_JSON" 2>/dev/null || true
    fi
    for extra in $EXTRA_STALE_FEEDS; do
        echo "${extra}:0"
    done
}

while IFS=: read -r name threshold zero_notice; do
    [ -z "$name" ] && continue
    # fromjson? silently skips malformed lines
    newest=$(jq -rR --arg f "$name" \
        'fromjson? | select(.feed == $f) | (.published // .polled_at)' \
        "$FEED_LOG" | sort | tail -1)
    if [ -z "$newest" ]; then
        [ "$zero_notice" = "1" ] && echo "- $name — no entries yet" >> "$TMP_STALE"
        continue
    fi
    newest_epoch=$(date -d "$newest" +%s 2>/dev/null) || continue
    age_days=$(( (NOW_EPOCH - newest_epoch) / 86400 ))
    if [ "$age_days" -gt "$threshold" ]; then
        echo "- $name — last entry ${newest%%T*} (${age_days}d ago, threshold ${threshold}d)" >> "$TMP_STALE"
    fi
done < <(stale_universe)

STALE_COUNT=$(wc -l < "$TMP_STALE" | tr -d ' ')

if [ "$NEW_COUNT" -le 0 ]; then
    if [ "$STALE_COUNT" -gt 0 ]; then
        {
            echo "# Intelligence Feed Digest — $(date +%Y-%m-%d)"
            echo ""
            echo "> No new entries. $STALE_COUNT feed(s) flagged stale. Generated $(date +%H:%M)."
            echo "> Delete this file when reviewed: \`rm ~/.claude/intelligence-feed-digest.md\`"
            echo ""
            echo "## ⚠ Stale feeds ($STALE_COUNT)"
            echo ""
            cat "$TMP_STALE"
        } > "$DIGEST"
        echo "[feed-index] No new entries; stale-only digest written ($STALE_COUNT flagged)"
    else
        echo "[feed-index] No new entries since last run ($TOTAL_LINES total)"
    fi
    exit 0
fi

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
        FEED_COUNT=$(jq -r "select(.feed == \"$feed\")" "$TMP_ENTRIES" | jq -rs 'length')
        echo "## $feed ($FEED_COUNT)"
        echo ""

        # High-signal: enriched output with stripped HTML content / LLM summaries
        IS_HIGH_SIGNAL=0
        for hs in $HIGH_SIGNAL_FEEDS; do
            [ "$feed" = "$hs" ] && IS_HIGH_SIGNAL=1 && break
        done

        if [ "$IS_HIGH_SIGNAL" = "1" ] && [ -f "$FORMAT_ENRICHED" ]; then
            jq -c "select(.feed == \"$feed\")" "$TMP_ENTRIES" \
                | python3 "$FORMAT_ENRICHED" "${SUMMARIES:-}" 10
        else
            # Low-signal feeds: title + link only (max 20 per feed)
            jq -r "select(.feed == \"$feed\") | \"\(.published // .polled_at | split(\"T\")[0]) — [\(.title | gsub(\"[\\n\\r]\"; \" \"))](\(.link))\"" \
                "$TMP_ENTRIES" | tail -20
            echo ""
        fi
    done <<< "$FEEDS"

    if [ "$STALE_COUNT" -gt 0 ]; then
        echo "## ⚠ Stale feeds ($STALE_COUNT)"
        echo ""
        cat "$TMP_STALE"
        echo ""
    fi
} > "$DIGEST"

echo "$TOTAL_LINES" > "$WATERMARK"
echo "[feed-index] Digest written to $DIGEST ($ENTRY_COUNT entries, $STALE_COUNT stale)"
