#!/usr/bin/env bash
set -euo pipefail

# backup-memory.sh — Rotating binary backup of ruflo memory database.
#
# Usage:
#   backup-memory.sh              # Backup to ~/.swarm/backups/ (or ~/.claude-flow/backups/)
#   backup-memory.sh --restore    # Restore latest backup passing integrity_check
#   backup-memory.sh --restore --date 20260330  # Restore specific date
#   backup-memory.sh --list       # List available backups
#
# Schedule: daily at 07:00 UTC via brana-scheduler (before sync-state push).
# Keeps last 7 dated copies. Skips 0-byte source files.

# Resolve DB path: ~/.swarm (current ruflo default) > ~/.claude-flow (legacy)
if [ -d "${HOME}/.swarm" ]; then
    DB_DIR="${RUFLO_DATA_DIR:-$HOME/.swarm}"
elif [ -d "${HOME}/.claude-flow" ]; then
    DB_DIR="${RUFLO_DATA_DIR:-$HOME/.claude-flow}"
else
    DB_DIR="${RUFLO_DATA_DIR:-$HOME/.swarm}"
fi
DB_FILE="$DB_DIR/memory.db"
BACKUP_DIR="$DB_DIR/backups"
MAX_BACKUPS=7

log() { echo "[backup-memory] $*" >&2; }

# A DB is healthy if PRAGMA integrity_check returns "ok". Real corruption is a
# malformed PAGE in a normal-sized file, so a size check alone misses it (t-2236).
# Degrade to healthy if sqlite3 is unavailable — never block backup on a missing
# tool. When a live writer holds a -wal sidecar, checking the live file directly
# false-positives (a mid-transaction read looks malformed to an external
# connection) — so instead we checkpoint a COPY of the db+wal pair (never the
# live files) and check that. This still avoids the live-writer false positive
# while actually catching real corruption under a live WAL — closing the gap
# that let a corrupt DB ride into the backup set unchecked for 10 days (t-2260).
db_is_healthy() {
    local db="$1"
    command -v sqlite3 >/dev/null 2>&1 || return 0

    if [ -f "${db}-wal" ]; then
        local tmpdir
        tmpdir=$(mktemp -d) || return 1
        cp "$db" "$tmpdir/copy.db" 2>/dev/null || { rm -rf "$tmpdir"; return 1; }
        cp "${db}-wal" "$tmpdir/copy.db-wal" 2>/dev/null || true
        [ -f "${db}-shm" ] && cp "${db}-shm" "$tmpdir/copy.db-shm" 2>/dev/null
        local result
        result=$(sqlite3 "$tmpdir/copy.db" "PRAGMA wal_checkpoint(TRUNCATE); PRAGMA integrity_check;" 2>/dev/null | tail -1)
        rm -rf "$tmpdir"
        [ "$result" = "ok" ]
        return
    fi

    sqlite3 "$db" "PRAGMA integrity_check;" 2>/dev/null | grep -q '^ok$'
}

cmd_backup() {
    mkdir -p "$BACKUP_DIR"

    if [ ! -f "$DB_FILE" ]; then
        log "skip — $DB_FILE does not exist"
        exit 0
    fi

    local size
    size=$(stat -c%s "$DB_FILE" 2>/dev/null) || size=0
    if [ "$size" -eq 0 ]; then
        log "skip — $DB_FILE is 0 bytes (corrupt). Not overwriting good backups."
        exit 0
    fi

    # Page-level corruption is non-zero, so the size check above misses it.
    # Never copy a corrupt DB into the backup set — that poisons every future
    # restore (the restore-newest loop, t-2236). db_is_healthy() itself handles
    # a live -wal sidecar by checkpointing a copy, so it's safe to call
    # unconditionally (t-2260 — the old skip-on-wal loophole let corruption
    # through unchecked for 10 days).
    if ! db_is_healthy "$DB_FILE"; then
        log "skip — $DB_FILE fails integrity_check (corrupt page). Not overwriting good backups."
        exit 0
    fi

    local date_stamp
    date_stamp=$(date -u +%Y%m%d)
    local backup_file="$BACKUP_DIR/memory_${date_stamp}.db"

    cp "$DB_FILE" "$backup_file"
    log "backed up: $backup_file ($size bytes)"

    # Rotate: keep only the newest MAX_BACKUPS files
    local count
    count=$(find "$BACKUP_DIR" -name "memory_*.db" -type f | wc -l)
    if [ "$count" -gt "$MAX_BACKUPS" ]; then
        local to_remove=$((count - MAX_BACKUPS))
        find "$BACKUP_DIR" -name "memory_*.db" -type f | sort | head -n "$to_remove" | while read -r old; do
            rm -f "$old"
            log "rotated: $(basename "$old")"
        done
    fi
}

cmd_restore() {
    local target_date="${1:-}"

    if [ -n "$target_date" ]; then
        local specific="$BACKUP_DIR/memory_${target_date}.db"
        if [ ! -f "$specific" ]; then
            log "error — no backup for date $target_date"
            cmd_list
            exit 1
        fi
        local size
        size=$(stat -c%s "$specific" 2>/dev/null) || size=0
        if [ "$size" -eq 0 ]; then
            log "error — backup $target_date is 0 bytes"
            exit 1
        fi
        cp "$specific" "$DB_FILE"
        log "restored: memory_${target_date}.db ($size bytes)"
        return
    fi

    # Find the latest backup that PASSES integrity_check — not just non-zero.
    # A corrupt page is non-zero; restoring it re-poisons the live DB and feeds
    # the corruption loop (t-2236). Walk newest-first, skip any that fail.
    local latest=""
    for f in $(find "$BACKUP_DIR" -name "memory_*.db" -type f 2>/dev/null | sort -r); do
        local size
        size=$(stat -c%s "$f" 2>/dev/null) || size=0
        if [ "$size" -gt 0 ] && db_is_healthy "$f"; then
            latest="$f"
            break
        fi
    done

    if [ -z "$latest" ]; then
        log "error — no healthy backups available in $BACKUP_DIR"
        exit 1
    fi

    local size
    size=$(stat -c%s "$latest" 2>/dev/null) || size=0
    cp "$latest" "$DB_FILE"
    log "restored: $(basename "$latest") ($size bytes)"
}

cmd_list() {
    if [ ! -d "$BACKUP_DIR" ]; then
        log "no backups directory at $BACKUP_DIR"
        exit 0
    fi

    echo "Available backups:"
    find "$BACKUP_DIR" -name "memory_*.db" -type f 2>/dev/null | sort | while read -r f; do
        local size
        size=$(stat -c%s "$f" 2>/dev/null) || size=0
        local name
        name=$(basename "$f")
        if [ "$size" -eq 0 ]; then
            echo "  $name  ${size} bytes  (CORRUPT)"
        else
            echo "  $name  ${size} bytes"
        fi
    done
}

# ── Main ──────────────────────────────────────────────────
case "${1:-backup}" in
    backup|"")
        cmd_backup
        ;;
    --restore)
        shift
        target=""
        if [[ "${1:-}" == "--date" ]] && [ -n "${2:-}" ]; then
            target="$2"
        fi
        cmd_restore "$target"
        ;;
    --list)
        cmd_list
        ;;
    --help|-h)
        echo "Usage: backup-memory.sh [backup|--restore [--date YYYYMMDD]|--list]"
        ;;
    *)
        echo "Unknown command: $1" >&2
        exit 1
        ;;
esac
