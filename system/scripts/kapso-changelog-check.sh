#!/usr/bin/env bash
# kapso-changelog-check.sh — Kapso changelog → feed-log.jsonl (t-2011, ADR-055)
#
# Kapso publishes no RSS. Their Mintlify docs serve raw markdown at
# https://docs.kapso.ai/changelog.md with <Update label="Mon D, YYYY"> blocks.
# This job diffs labels against local state and appends FeedLogEntry-shaped
# JSONL (feed: kapso-changelog) to feed-log.jsonl, upstream of feed-index.
#
# State:  ~/.claude/scheduler/state/kapso-changelog-scrape.json
#         (intentionally NOT the CLI's state/{name}.json convention —
#          kapso-changelog is not a feeds.json-registered feed; brana feed
#          status will not show it. Staleness coverage comes from
#          EXTRA_STALE_FEEDS in feed-index.sh.)
#
# Usage: ./system/scripts/kapso-changelog-check.sh [--dry-run] [--source FILE]
#   --dry-run      Print would-be entries; no writes
#   --source FILE  Parse a local file instead of fetching (tests)
#
# Failure semantics: fetch failure exits 1 with FETCH FAILED, state untouched —
# distinguishes network failure (scheduler log) from content staleness (digest).

set -euo pipefail

URL="https://docs.kapso.ai/changelog.md"
LINK="https://docs.kapso.ai/changelog"
STATE="$HOME/.claude/scheduler/state/kapso-changelog-scrape.json"
FEED_LOG="$HOME/.claude/scheduler/feed-log.jsonl"

DRY_RUN=0
SOURCE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --source)  shift; SOURCE="${1:-}" ;;
        *) echo "[kapso-check] unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

mkdir -p "$(dirname "$STATE")"

TMP_MD=$(mktemp)
TMP_NEW=$(mktemp)
TMP_STATE=$(mktemp)
trap 'rm -f "$TMP_MD" "$TMP_NEW" "$TMP_STATE"' EXIT

if [ -n "$SOURCE" ]; then
    cp "$SOURCE" "$TMP_MD" 2>/dev/null || { echo "[kapso-check] FETCH FAILED: cannot read $SOURCE"; exit 1; }
else
    curl -sfL --max-time 30 "$URL" -o "$TMP_MD" || { echo "[kapso-check] FETCH FAILED: $URL"; exit 1; }
fi

# Parse Update blocks; emit new entries (JSONL) + updated state
python3 - "$TMP_MD" "$STATE" "$TMP_NEW" "$TMP_STATE" <<'PY'
import json, re, sys
from datetime import datetime, timezone

md_path, state_path, new_path, state_out_path = sys.argv[1:5]
md = open(md_path, encoding="utf-8").read()

try:
    with open(state_path, encoding="utf-8") as f:
        seen = set(json.load(f).get("seen_labels", []))
except (FileNotFoundError, json.JSONDecodeError):
    seen = set()

blocks = re.findall(r'<Update label="([^"]+)">(.*?)</Update>', md, re.DOTALL)
if not blocks and "<Update" in md:
    # Structure changed — fail loudly so the scheduler log shows it
    print("PARSE FAILED: Update blocks present but unparseable", file=sys.stderr)
    sys.exit(1)

polled_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
new_entries = []
for label, body in blocks:
    if label in seen:
        continue
    # Labels are "Jun 9, 2026" or "Nov 27, 2025 - 11:00" — strip any time suffix
    date_part = label.split(" - ")[0].strip()
    try:
        published = datetime.strptime(date_part, "%b %d, %Y").strftime("%Y-%m-%dT00:00:00Z")
    except ValueError:
        published = None
    body_text = body.strip()
    bolds = re.findall(r'\*\*(.+?)\*\*', body_text)
    title = f"Kapso changelog {label}: " + ("; ".join(bolds)[:160] if bolds else "update")
    new_entries.append({
        "feed": "kapso-changelog",
        "title": title,
        "link": "https://docs.kapso.ai/changelog",
        "published": published,
        "polled_at": polled_at,
        "summary": None,
        "content": body_text[:4000],
    })
    seen.add(label)

# Oldest-first so feed-log stays chronological within the batch
new_entries.reverse()
with open(new_path, "w", encoding="utf-8") as f:
    for e in new_entries:
        f.write(json.dumps(e, ensure_ascii=False) + "\n")

with open(state_out_path, "w", encoding="utf-8") as f:
    json.dump({"seen_labels": sorted(seen), "last_check": polled_at}, f, indent=2)

print(f"{len(new_entries)} new")
PY

NEW_COUNT=$(wc -l < "$TMP_NEW" | tr -d ' ')
echo "[kapso-check] $NEW_COUNT new update(s)"

if [ "$DRY_RUN" = "1" ]; then
    cat "$TMP_NEW"
    exit 0
fi

if [ "$NEW_COUNT" -gt 0 ]; then
    cat "$TMP_NEW" >> "$FEED_LOG"
fi
mv "$TMP_STATE" "$STATE"
echo "[kapso-check] state updated ($STATE)"
