#!/usr/bin/env bash
# feed-summarize.sh — Enrich anthropic-news feed entries with claude -p summaries
#
# For each new anthropic-news entry not yet in feed-summaries.jsonl:
#   1. Fetch article URL
#   2. Strip HTML to readable text
#   3. Summarize via `claude -p` (2-3 sentences)
#   4. Append to ~/.claude/scheduler/feed-summaries.jsonl
#
# feed-index.sh reads feed-summaries.jsonl when building the digest.
#
# Watermark: ~/.claude/scheduler/state/feed-summarize-watermark (line count)
# Output:    ~/.claude/scheduler/feed-summaries.jsonl
#
# Usage: ./system/scripts/feed-summarize.sh [--dry-run] [--force]
#   --dry-run  Show what would be summarized, no writes
#   --force    Re-process all entries (ignores watermark, respects dedup)

set -euo pipefail

FEED_LOG="${FEED_LOG:-$HOME/.claude/scheduler/feed-log.jsonl}"
SUMMARIES="${SUMMARIES:-$HOME/.claude/scheduler/feed-summaries.jsonl}"
WATERMARK="${WATERMARK:-$HOME/.claude/scheduler/state/feed-summarize-watermark}"
CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
MAX_CONTENT_CHARS=3000
FETCH_TIMEOUT=15
SUMMARIZE_TIMEOUT=45
# Per-run cap (t-2076): a backlog of unsummarized articles must not turn every
# run into a job timeout. A capped run exits 0 WITHOUT advancing the watermark —
# the link-dedup set makes the rescan cheap and later runs drain the rest.
MAX_PER_RUN="${FEED_SUMMARIZE_MAX:-20}"

# Feeds that require URL fetch + claude -p summarization
# (feeds with full content/summary already in the entry are handled by feed-index.sh directly)
SUMMARIZE_FEEDS="anthropic-news"

mkdir -p "$(dirname "$WATERMARK")"
touch "$SUMMARIES"

DRY_RUN=0
FORCE=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --force)   FORCE=1 ;;
    esac
done

# ── Guard ─────────────────────────────────────────────────────────────────────

if [ ! -f "$FEED_LOG" ]; then
    echo "[feed-summarize] No feed log at $FEED_LOG — run 'brana feed poll --all' first"
    exit 0
fi

if [ ! -x "$CLAUDE_BIN" ] && ! command -v claude &>/dev/null; then
    echo "[feed-summarize] claude binary not found — skipping summarization"
    exit 0
fi

CLAUDE="${CLAUDE_BIN:-$(command -v claude)}"

# ── Watermark ─────────────────────────────────────────────────────────────────

TOTAL_LINES=$(wc -l < "$FEED_LOG")

if [ "$FORCE" = "1" ]; then
    START_LINE=1
else
    LAST=$(cat "$WATERMARK" 2>/dev/null | tr -d '[:space:]') || LAST=0
    START_LINE=$((LAST + 1))
fi

NEW_COUNT=$((TOTAL_LINES - START_LINE + 1))
if [ "$NEW_COUNT" -le 0 ]; then
    echo "[feed-summarize] No new entries since last run ($TOTAL_LINES total)"
    exit 0
fi

# ── Extract new entries ───────────────────────────────────────────────────────

TMP_ENTRIES=$(mktemp /tmp/feed-summarize-entries-XXXXXX.jsonl)
trap 'rm -f "$TMP_ENTRIES"' EXIT

sed -n "${START_LINE},${TOTAL_LINES}p" "$FEED_LOG" > "$TMP_ENTRIES"

# Filter to valid JSON and target feeds only
TMP_FILTERED=$(mktemp /tmp/feed-summarize-filtered-XXXXXX.jsonl)
trap 'rm -f "$TMP_ENTRIES" "$TMP_FILTERED"' EXIT

while IFS= read -r line; do
    [ -z "$line" ] && continue
    FEED_NAME=$(echo "$line" | jq -r '.feed // empty' 2>/dev/null) || continue
    for sf in $SUMMARIZE_FEEDS; do
        if [ "$FEED_NAME" = "$sf" ]; then
            echo "$line" >> "$TMP_FILTERED"
            break
        fi
    done
done < "$TMP_ENTRIES"

TARGET_COUNT=$(wc -l < "$TMP_FILTERED" | tr -d ' ')
if [ "$TARGET_COUNT" -eq 0 ]; then
    echo "[feed-summarize] No new target-feed entries (checked ${NEW_COUNT} entries from line ${START_LINE})"
    echo "$TOTAL_LINES" > "$WATERMARK"
    exit 0
fi

echo "[feed-summarize] Found $TARGET_COUNT new entries to check for summarization"

# ── Build set of already-summarized links ─────────────────────────────────────

TMP_DONE_LINKS=$(mktemp /tmp/feed-summarize-done-XXXXXX.txt)
trap 'rm -f "$TMP_ENTRIES" "$TMP_FILTERED" "$TMP_DONE_LINKS"' EXIT

jq -r '.link // empty' "$SUMMARIES" 2>/dev/null | sort -u > "$TMP_DONE_LINKS" || true

# ── HTML fetch + strip helper ──────────────────────────────────────────────────

fetch_and_strip() {
    local url="$1"
    local max_chars="${2:-$MAX_CONTENT_CHARS}"
    python3 - "$url" "$max_chars" <<'PYEOF'
import sys, re, urllib.request
from html.parser import HTMLParser

class Stripper(HTMLParser):
    SKIP_TAGS = {'script','style','nav','header','footer','noscript','meta','link','aside'}
    def __init__(self):
        super().__init__()
        self.parts = []
        self._depth = 0
    def handle_starttag(self, tag, attrs):
        if tag.lower() in self.SKIP_TAGS:
            self._depth += 1
    def handle_endtag(self, tag):
        if tag.lower() in self.SKIP_TAGS and self._depth > 0:
            self._depth -= 1
    def handle_data(self, data):
        if self._depth == 0:
            self.parts.append(data)

url = sys.argv[1]
max_chars = int(sys.argv[2]) if len(sys.argv) > 2 else 3000

req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (compatible; brana-feed/1.0)'})
try:
    with urllib.request.urlopen(req, timeout=15) as r:
        html = r.read().decode('utf-8', errors='replace')
except Exception as e:
    sys.stderr.write(f"fetch error: {e}\n")
    sys.exit(1)

p = Stripper()
p.feed(html)
text = ' '.join(p.parts)
text = re.sub(r'\s+', ' ', text).strip()
sys.stdout.write(text[:max_chars])
PYEOF
}

# ── Summarize each new entry ───────────────────────────────────────────────────

SUMMARIZED=0
SKIPPED=0
FAILED=0
CAPPED=0

while IFS= read -r entry; do
    LINK=$(echo "$entry" | jq -r '.link // empty')
    TITLE=$(echo "$entry" | jq -r '.title // ""')
    FEED=$(echo "$entry" | jq -r '.feed // ""')

    [ -z "$LINK" ] && continue

    # Skip already-summarized
    if grep -qF "$LINK" "$TMP_DONE_LINKS" 2>/dev/null; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    if [ "$DRY_RUN" = "1" ]; then
        echo "[dry-run] would summarize: $TITLE"
        echo "          $LINK"
        continue
    fi

    # Fetch content
    CONTENT=$(fetch_and_strip "$LINK" "$MAX_CONTENT_CHARS" 2>/dev/null) || {
        echo "[feed-summarize] fetch failed (skipping): $TITLE"
        FAILED=$((FAILED + 1))
        continue
    }

    if [ -z "$CONTENT" ] || [ "${#CONTENT}" -lt 100 ]; then
        echo "[feed-summarize] insufficient content (skipping): $TITLE"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Summarize via claude -p
    PROMPT="Summarize in 2-3 sentences for an AI developer tracking Anthropic releases. Be specific: mention model names, new capabilities, pricing changes, or breaking changes if present. Skip generic phrases like 'this article discusses'.

Feed: $FEED
Title: $TITLE
URL: $LINK

Content:
$CONTENT

Summary (2-3 sentences only, no preamble):"

    SUMMARY=$(echo "$PROMPT" | timeout "$SUMMARIZE_TIMEOUT" "$CLAUDE" -p --output-format text 2>/dev/null) || {
        echo "[feed-summarize] claude failed (skipping): $TITLE"
        FAILED=$((FAILED + 1))
        continue
    }

    if [ -z "$SUMMARY" ]; then
        echo "[feed-summarize] empty summary (skipping): $TITLE"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Append to summaries file
    python3 -c "
import json, sys
print(json.dumps({
    'link':         sys.argv[1],
    'title':        sys.argv[2],
    'feed':         sys.argv[3],
    'summary':      sys.argv[4],
    'summarized_at': sys.argv[5]
}))
" "$LINK" "$TITLE" "$FEED" "$SUMMARY" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$SUMMARIES"

    echo "[feed-summarize] summarized: $TITLE"
    SUMMARIZED=$((SUMMARIZED + 1))

    # Add to done set to avoid re-processing within this run
    echo "$LINK" >> "$TMP_DONE_LINKS"

    if [ "$SUMMARIZED" -ge "$MAX_PER_RUN" ]; then
        echo "[feed-summarize] per-run cap reached ($MAX_PER_RUN) — exiting early, watermark unchanged"
        CAPPED=1
        break
    fi

done < "$TMP_FILTERED"

# ── Update watermark (skip on capped runs — unchecked entries remain) ─────────

if [ "$CAPPED" = "0" ]; then
    echo "$TOTAL_LINES" > "$WATERMARK"
fi

echo "[feed-summarize] done — summarized: $SUMMARIZED, already-done: $SKIPPED, failed: $FAILED, capped: $CAPPED"
