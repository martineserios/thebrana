#!/usr/bin/env bash
set -euo pipefail
# The ledger carries task text that can be sensitive: everything this script creates
# (dirs, copies, pre-restore copies) is owner-only from the moment it exists — no chmod-after.
umask 077

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
# Backups: $TASKS_JSON_BACKUP_DIR (default ~/.claude/tasks-json-backups)/<basename>-<sha1(common-root)[:8]>/tasks.json.<UTC>.json
# The dir is keyed by the repo's resolved path (hash), not its bare basename, so two repos that
# share a name never intermix backups — and a `.repo` marker records the path; restore refuses on
# mismatch. Dirs are 700, copies 600 (umask 077). Keeps the newest $MAX_BACKUPS (default 48 —
# two days at hourly cadence, ~250 MB at 5 MB each). --restore accepts only a backup filename
# inside that dir (or --latest), never an arbitrary path.
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
# Key by resolved path, not bare basename (Gate 3 security finding, 2026-09-07): two repos named
# alike must never share — or restore across — a backup dir.
SLUG="$(basename "$common_root")-$(printf '%s' "$common_root" | sha1sum | cut -c1-8)"
DEST="$BACKUP_ROOT/$SLUG"
MARKER="$DEST/.repo"

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
        if [ -f "$MARKER" ] && [ "$(cat "$MARKER")" != "$common_root" ]; then
            echo "ERROR: $DEST belongs to $(cat "$MARKER"), not $common_root — refusing to restore across repos" >&2; exit 1
        fi
        # Only a filename inside $DEST (or --latest) — never an arbitrary path (no provenance otherwise).
        if [ -z "$RESTORE_ARG" ] || [ "$RESTORE_ARG" = "--latest" ]; then src=$(newest_backup); else src="$DEST/$(basename "$RESTORE_ARG")"; fi
        [ -n "$src" ] && [ -f "$src" ] || { echo "ERROR: backup not found in $DEST: ${RESTORE_ARG:-latest}" >&2; exit 1; }
        [ "$(count_tasks "$src")" != "invalid" ] || { echo "ERROR: backup is not valid JSON: $src" >&2; exit 1; }
        if [ -f "$LEDGER" ]; then cp "$LEDGER" "$LEDGER.pre-restore.$(date -u +%Y%m%dT%H%M%SZ)"; fi   # plain cp: 600 via umask, not the ledger's mode
        mkdir -p "$(dirname "$LEDGER")"
        cp "$src" "$LEDGER.tmp.$$" && mv "$LEDGER.tmp.$$" "$LEDGER"
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
        mkdir -p "$DEST"                       # 700 via umask 077
        if [ -f "$MARKER" ] && [ "$(cat "$MARKER")" != "$common_root" ]; then
            echo "REFUSED: $DEST belongs to $(cat "$MARKER"), not $common_root" >&2; exit 2
        fi
        [ -f "$MARKER" ] || printf '%s\n' "$common_root" > "$MARKER"
        out="$DEST/tasks.json.$(date -u +%Y%m%dT%H%M%SZ).json"
        cp "$LEDGER" "$out.tmp" && mv "$out.tmp" "$out"   # plain cp: the copy is 600 regardless of the ledger's mode
        # rotate: keep newest MAX_BACKUPS
        ls -1t "$DEST"/tasks.json.*.json 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | while IFS= read -r old; do rm -f "$old"; done
        kept=$(ls -1 "$DEST"/tasks.json.*.json 2>/dev/null | wc -l | tr -d ' ')
        echo "backed up $LEDGER ($n tasks) → $out; $kept kept (max $MAX_BACKUPS)"
        exit 0 ;;
esac
