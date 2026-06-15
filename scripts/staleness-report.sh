#!/usr/bin/env bash
# staleness-report.sh — Layer-aware doc staleness check (doc 25, #45).
#
# Layers and thresholds (docs/25-self-documentation.md):
#   Roadmap (17,18,19,24):        30 days
#   Reflection (08,14,29,31,32):  90 days
#   Dimension (01-07,09-13,15-16,20-23,25-28,33-37): 180 days
#
# Two-tier output: WARN at 80% of threshold, STALE past threshold.
# Summary line: "N docs checked, X stale, Y warn"
# Always exits 0 — staleness is a report, not a failure.

set -uo pipefail

DOCS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docs"
TODAY_EPOCH=$(date +%s)

# Classify a doc number to layer. Returns: roadmap, reflection, dimension, or unknown.
classify_layer() {
    local num="$1"
    case "$num" in
        17|18|19|24)          echo "roadmap" ;;
        08|14|29|31|32)       echo "reflection" ;;
        0[1-7]|09|1[0-3]|15|16|2[0-3]|25|26|27|28|3[3-7]) echo "dimension" ;;
        *)                    echo "unknown" ;;
    esac
}

threshold_days() {
    case "$1" in
        roadmap)    echo 30 ;;
        reflection) echo 90 ;;
        dimension)  echo 180 ;;
        *)          echo 180 ;;
    esac
}

CHECKED=0
STALE=0
WARN=0

for doc in "$DOCS_DIR"/*.md; do
    [ -f "$doc" ] || continue
    base="$(basename "$doc")"

    # Extract leading doc number (e.g. "18-lean-roadmap.md" → "18")
    num="${base%%-*}"
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        continue
    fi
    num=$(printf "%02d" "$num" 2>/dev/null) || continue

    layer="$(classify_layer "$num")"
    [ "$layer" = "unknown" ] && continue

    threshold="$(threshold_days "$layer")"
    warn_threshold=$(( threshold * 80 / 100 ))

    # Last git modification in epoch seconds
    last_commit_date="$(git -C "$DOCS_DIR/.." log -1 --format="%ct" -- "$doc" 2>/dev/null)"
    if [ -z "$last_commit_date" ] || [ "$last_commit_date" = "" ]; then
        continue
    fi

    days_since=$(( (TODAY_EPOCH - last_commit_date) / 86400 ))
    CHECKED=$((CHECKED + 1))

    if [ "$days_since" -gt "$threshold" ]; then
        echo "STALE [$layer] $base — ${days_since}d (threshold: ${threshold}d)"
        STALE=$((STALE + 1))
    elif [ "$days_since" -gt "$warn_threshold" ]; then
        echo "WARN  [$layer] $base — ${days_since}d (threshold: ${threshold}d)"
        WARN=$((WARN + 1))
    fi
done

echo "$CHECKED docs checked, $STALE stale, $WARN warn"
exit 0
