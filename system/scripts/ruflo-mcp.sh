#!/bin/bash
# Wrapper: ensures ruflo MCP server reads ~/.swarm/memory.db
# instead of .swarm/ relative to whatever CWD CC launches from.
# Resolves ruflo from nvm or PATH — no hardcoded paths.
#
# IMPORTANT: must use `exec` to preserve stdin/stdout pipes for MCP stdio.
# Earlier versions backgrounded ruflo (`ruflo & wait`) to support SIGTERM/SIGHUP
# restart loops — that pattern silently broke JSON-RPC stdin delivery, so the
# MCP handshake never completed and ruflo showed as "failed" in /mcp.
# Restart on CC bug #40207 is handled by the user via /mcp reconnect.
# Use CLAUDE_PROJECT_DIR (CC-injected since v2.1.139) for project root so ruflo's
# own CWD heuristic resolves correctly; fall back to HOME for ~/.swarm/memory.db.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR:-}" ]; then
    cd "$CLAUDE_PROJECT_DIR"
else
    cd "$HOME"
fi

# Hard mutex: only ONE ruflo instance may write to memory.db at a time.
# SQLite WAL allows concurrent readers but concurrent writers corrupt B-trees —
# confirmed by two events: 2026-04-06, 2026-06-07. Advisory PID file was
# insufficient; replaced with flock (c6a66b76). If CC spawns multiple sessions,
# only the first gets ruflo; later sessions see "failed" in /mcp — run
# /mcp reconnect to retry after the prior session closes.
LOCKFILE="$HOME/.swarm/ruflo-mcp.lock"
PIDFILE="$HOME/.swarm/ruflo-mcp.pid"
mkdir -p "$HOME/.swarm"
exec 9>"$LOCKFILE"
if ! flock -n 9; then
    existing_pid="$(cat "$PIDFILE" 2>/dev/null || echo unknown)"
    echo "[ruflo-mcp] Another instance is running (PID: $existing_pid). Exiting to prevent DB corruption." >&2
    exit 1
fi
echo $$ > "$PIDFILE"
trap 'rm -f "$LOCKFILE" "$PIDFILE"' EXIT

# Orphan sweep (t-1858): kill pre-flock ruflo instances that bypass the mutex.
# We hold the lock, so any OTHER ruflo process is an orphan with no flock —
# pre-c6a66b76 instances can corrupt the DB by writing concurrently.
while IFS= read -r orphan_pid; do
    [ "$orphan_pid" -eq "$$" ] && continue
    echo "[ruflo-mcp] Killing pre-flock orphan (PID: $orphan_pid)." >&2
    kill "$orphan_pid" 2>/dev/null || true
done < <(pgrep -f 'ruflo mcp start' 2>/dev/null || true)

DB_PATH="$HOME/.swarm/memory.db"
BACKUP_DIR="$HOME/.swarm/backups"
mkdir -p "$BACKUP_DIR"

# Integrity check: if DB is malformed, recover from most recent backup.
if [ -f "$DB_PATH" ]; then
    if ! sqlite3 "$DB_PATH" "PRAGMA integrity_check;" 2>/dev/null | grep -q "^ok$"; then
        echo "[ruflo-mcp] memory.db integrity check failed — recovering." >&2
        mv "$DB_PATH" "${DB_PATH}.corrupt-$(date +%Y-%m-%d)" 2>/dev/null || true
        LATEST_BACKUP="$(ls -t "$BACKUP_DIR"/memory_*.db 2>/dev/null | head -1)"
        if [ -n "$LATEST_BACKUP" ]; then
            cp "$LATEST_BACKUP" "$DB_PATH" && chmod 600 "$DB_PATH"
            echo "[ruflo-mcp] Restored from backup: $LATEST_BACKUP" >&2
        else
            echo "[ruflo-mcp] WARN: No backup found — ruflo starts with empty DB." >&2
        fi
    fi
fi

# Daily backup: snapshot memory.db before ruflo opens it. Keep 14 days.
TODAY="$(date +%Y%m%d)"
BACKUP_FILE="$BACKUP_DIR/memory_${TODAY}.db"
if [ -f "$DB_PATH" ] && [ ! -f "$BACKUP_FILE" ]; then
    cp "$DB_PATH" "$BACKUP_FILE" && chmod 600 "$BACKUP_FILE" \
        && echo "[ruflo-mcp] Backup written: $BACKUP_FILE" >&2 \
        || echo "[ruflo-mcp] WARN: daily backup failed" >&2
fi
ls -t "$BACKUP_DIR"/memory_*.db 2>/dev/null | tail -n +15 | xargs rm -f 2>/dev/null || true

# Resolution order:
#   1. nvm default node's bin/
#   2. any nvm-installed version that has ruflo (newest first)
#   3. PATH
if [ -f "$HOME/.nvm/nvm.sh" ]; then
    export NVM_DIR="$HOME/.nvm"
    . "$NVM_DIR/nvm.sh" --no-use 2>/dev/null
    RUFLO="$(nvm which default 2>/dev/null | sed 's|/node$||')/ruflo"
fi
if [ ! -x "${RUFLO:-}" ] && [ -d "$HOME/.nvm/versions/node" ]; then
    # Walk installed versions newest-first; stop at first hit
    NVM_DEFAULT_BIN="$(nvm which default 2>/dev/null | sed 's|/node$||')"
    while IFS= read -r node_bin; do
        candidate="${node_bin%/node}/ruflo"
        if [ -x "$candidate" ]; then
            RUFLO="$candidate"
            # Warn if this is not the nvm default — ruflo needs installing there
            actual_bin="${node_bin%/node}"
            if [ "$actual_bin" != "$NVM_DEFAULT_BIN" ]; then
                actual_ver="$(basename "$(dirname "$actual_bin")")"
                default_ver="$(basename "$(dirname "$NVM_DEFAULT_BIN")")"
                echo "[ruflo-mcp] WARN: ruflo found in nvm $actual_ver but nvm default is $default_ver — run: nvm use $actual_ver && npm install -g ruflo && nvm use default" >&2
            fi
            break
        fi
    done < <(find "$HOME/.nvm/versions/node" -name "node" -path "*/bin/node" | sort -rV)
fi
[ ! -x "${RUFLO:-}" ] && RUFLO="$(command -v ruflo 2>/dev/null)"
[ ! -x "${RUFLO:-}" ] && { echo "ruflo not found in nvm or PATH" >&2; exit 1; }

exec "$RUFLO" "$@"
