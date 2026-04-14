#!/usr/bin/env bash
# Monthly sweep: archive stale feedback_*.md files.
# Spec: ADR-037 (t-1243), task t-1246
#
# Behavior:
#   - Files not accessed in 90+ days → archived (not deleted)
#   - Cap: max 15 files per run (avoid session saturation)
#   - Dry-run mode: --dry-run shows what would be archived
#
# Usage:
#   bash sweep-feedback-files.sh [--dry-run] [--days N] [--cap N]
#
# Schedule: run monthly via /brana:memory review or cron.

set -euo pipefail

MEMORY_DIR="${HOME}/.claude/projects/-home-martineserios-enter-thebrana-thebrana/memory"
ARCHIVE_DIR="${MEMORY_DIR}/archive"
DRY_RUN=false
STALE_DAYS=90
CAP=15
ARCHIVED=0
SKIPPED=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --days)    STALE_DAYS="$2"; shift 2 ;;
        --cap)     CAP="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ ! -d "$MEMORY_DIR" ]; then
    echo "Memory dir not found: $MEMORY_DIR"
    exit 1
fi

if [ "$DRY_RUN" = false ]; then
    mkdir -p "$ARCHIVE_DIR"
fi

echo "=== feedback_*.md sweep ==="
echo "Stale threshold: ${STALE_DAYS} days | Cap: ${CAP} | Dry-run: ${DRY_RUN}"
echo ""

# Find feedback_*.md files, sorted by access time (oldest first)
while IFS= read -r file; do
    [ "$ARCHIVED" -ge "$CAP" ] && break

    filename=$(basename "$file")

    # Check access time (atime) — days since last access
    if command -v stat &>/dev/null; then
        # Linux stat
        atime_epoch=$(stat -c %X "$file" 2>/dev/null) || atime_epoch=0
        now_epoch=$(date +%s)
        age_days=$(( (now_epoch - atime_epoch) / 86400 ))
    else
        age_days=999  # fallback: treat as stale if stat unavailable
    fi

    if [ "$age_days" -lt "$STALE_DAYS" ]; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] would archive: $filename (${age_days}d old)"
    else
        mv "$file" "$ARCHIVE_DIR/$filename"
        echo "  archived: $filename (${age_days}d old)"
    fi

    ARCHIVED=$((ARCHIVED + 1))
done < <(find "$MEMORY_DIR" -maxdepth 1 -name "feedback_*.md" -printf '%A@\t%p\n' 2>/dev/null | sort -n | cut -f2)

echo ""
echo "Done: ${ARCHIVED} archived, ${SKIPPED} skipped (< ${STALE_DAYS}d old)"
if [ "$ARCHIVED" -ge "$CAP" ]; then
    echo "Cap reached (${CAP}). Run again next month for remaining files."
fi
echo "Archive dir: ${ARCHIVE_DIR}"
