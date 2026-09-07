#!/usr/bin/env bash
set -euo pipefail

# tasks-json-backup.sh — Rotating backup of a repo's live backlog ledger (ADR-094, t-3326 interim).
#
# The ledger is untracked from git (ADR-091) and, until t-3324 moves it under .git/brana/,
# lives at <common-root>/.claude/tasks.json where a `git checkout` of any ref that tracks
# that path silently overwrites it (2026-09-07 incident). This job bounds the loss window
# to one schedule tick. It is deliberately dumb: copy, verify, rotate, refuse to bury good
# copies under a wiped one.
#
# Usage:
#   tasks-json-backup.sh [--repo <path>]            # back up (default repo: cwd's git common root)
#   tasks-json-backup.sh --list [--repo <path>]     # list backups, newest first
#   tasks-json-backup.sh --restore [--latest | <file>] [--repo <path>]
#   tasks-json-backup.sh --check [--repo <path>]    # print ledger path/count/newest backup age; exit 2 on collapse
#
# Backups: $TASKS_JSON_BACKUP_DIR (default ~/.claude/tasks-json-backups)/<repo-slug>/tasks.json.<UTC>.json
# Keeps the newest $MAX_BACKUPS (default 48 — two days at hourly cadence, ~250 MB at 5 MB each).
#
# Refusals (exit 2, backups untouched): source missing, source not valid JSON, source has 0 tasks
# while the newest backup has >0 — a wiped ledger must never rotate the good copies out.

MAX_BACKUPS="${MAX_BACKUPS:-48}"
BACKUP_ROOT="${TASKS_JSON_BACKUP_DIR:-$HOME/.claude/tasks-json-backups}"

MODE="backup"; REPO=""; RESTORE_ARG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --repo) REPO="$2"; shift 2 ;;
        --list) MODE="list"; shift ;;
        --check) MODE="check"; shift ;;
        --restore) MODE="restore"; shift; if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then RESTORE_ARG="$1"; shift; fi ;;
        --latest) RESTORE_ARG="--latest"; shift ;;
        -h|--help) sed -n '3,22p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
done

# Resolve the canonical ledger: prefer the ADR-094 location once it exists, else ADR-091's.
common_dir=$(git -C "${REPO:-.}" rev-parse --git-common-dir 2>/dev/null || true)
if [ -z "$common_dir" ]; then echo "ERROR: ${REPO:-.} is not inside a git repo" >&2; exit 1; fi
case "$common_dir" in /*) ;; *) common_dir="$(cd "${REPO:-.}" && cd "$common_dir" && pwd)" ;; esac
common_root=$(dirname "$common_dir")
if [ -f "$common_dir/brana/tasks.json" ]; then
    LEDGER="$common_dir/brana/tasks.json"
else
    LEDGER="$common_root/.claude/tasks.json"
fi
SLUG=$(basename "$common_root")
DEST="$BACKUP_ROOT/$SLUG"

count_tasks() {   # $1 = file → prints task count, or "invalid"
    python3 -c 'import json,sys
try:
    d=json.load(open(sys.argv[1])); t=d.get("tasks"); print(len(t) if isinstance(t,list) else "invalid")
except Exception: print("invalid")' "$1" 2>/dev/null || echo invalid
}
newest_backup() { ls -1t "$DEST"/tasks.json.*.json 2>/dev/null | head -n1 || true; }

case "$MODE" in
    list)
        [ -d "$DEST" ] || { echo "no backups for $SLUG under $DEST"; exit 0; }
        for f in $(ls -1t "$DEST"/tasks.json.*.json 2>/dev/null); do
            printf '%s  %s tasks  %s\n' "$(basename "$f")" "$(count_tasks "$f")" "$(du -h "$f" | cut -f1)"
        done
        exit 0 ;;
    check)
        n=$( [ -f "$LEDGER" ] && count_tasks "$LEDGER" || echo missing )
        nb=$(newest_backup)
        if [ -n "$nb" ]; then
            age=$(( $(date +%s) - $(stat -c %Y "$nb") ))
            echo "ledger: $LEDGER · $n tasks · newest backup $(basename "$nb") ($(count_tasks "$nb") tasks, $((age/60)) min ago)"
            bn=$(count_tasks "$nb")
            if [ "$n" = "missing" ] || [ "$n" = "invalid" ] || { [ "$bn" != "invalid" ] && [ "$n" -lt $(( bn / 2 )) ]; }; then
                echo "COLLAPSE: ledger ($n) vs newest backup ($bn) — restore with: $0 --restore --latest --repo $common_root" >&2
                exit 2
            fi
        else
            echo "ledger: $LEDGER · $n tasks · no backups yet"
        fi
        exit 0 ;;
    restore)
        [ -d "$DEST" ] || { echo "ERROR: no backups for $SLUG under $DEST" >&2; exit 1; }
        if [ -z "$RESTORE_ARG" ] || [ "$RESTORE_ARG" = "--latest" ]; then src=$(newest_backup); else src="$RESTORE_ARG"; [ -f "$src" ] || src="$DEST/$RESTORE_ARG"; fi
        [ -n "$src" ] && [ -f "$src" ] || { echo "ERROR: backup not found: ${RESTORE_ARG:-latest}" >&2; exit 1; }
        [ "$(count_tasks "$src")" != "invalid" ] || { echo "ERROR: backup is not valid JSON: $src" >&2; exit 1; }
        if [ -f "$LEDGER" ]; then cp -p "$LEDGER" "$LEDGER.pre-restore.$(date -u +%Y%m%dT%H%M%SZ)"; fi
        mkdir -p "$(dirname "$LEDGER")"
        cp -p "$src" "$LEDGER.tmp.$$" && mv "$LEDGER.tmp.$$" "$LEDGER"
        echo "restored $LEDGER from $(basename "$src") ($(count_tasks "$LEDGER") tasks); previous copy kept as $LEDGER.pre-restore.*"
        exit 0 ;;
    backup)
        [ -f "$LEDGER" ] || { echo "REFUSED: ledger missing at $LEDGER (nothing to back up; restore it first)" >&2; exit 2; }
        n=$(count_tasks "$LEDGER")
        [ "$n" != "invalid" ] || { echo "REFUSED: $LEDGER is not valid ledger JSON" >&2; exit 2; }
        nb=$(newest_backup)
        if [ -n "$nb" ]; then
            bn=$(count_tasks "$nb")
            if [ "$n" -eq 0 ] && [ "$bn" != "invalid" ] && [ "$bn" -gt 0 ]; then
                echo "REFUSED: ledger has 0 tasks but newest backup $(basename "$nb") has $bn — not rotating good copies out of the way of a wiped ledger. Investigate; restore with: $0 --restore --latest --repo $common_root" >&2
                exit 2
            fi
        fi
        mkdir -p "$DEST"
        out="$DEST/tasks.json.$(date -u +%Y%m%dT%H%M%SZ).json"
        cp -p "$LEDGER" "$out.tmp" && mv "$out.tmp" "$out"
        # rotate: keep newest MAX_BACKUPS
        ls -1t "$DEST"/tasks.json.*.json 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | while IFS= read -r old; do rm -f "$old"; done
        kept=$(ls -1 "$DEST"/tasks.json.*.json 2>/dev/null | wc -l | tr -d ' ')
        echo "backed up $LEDGER ($n tasks) → $out; $kept kept (max $MAX_BACKUPS)"
        exit 0 ;;
esac
