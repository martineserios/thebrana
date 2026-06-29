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
#
# Multiple concurrent sessions: ruflo uses SQLite WAL mode, which serializes
# concurrent writes safely. The prior flock mutex (c6a66b76) and orphan sweep
# (41d7a9fc) were removed — the orphan sweep killed live writers and caused the
# very corruption it was meant to prevent (confirmed June 13 2026 with flock active).
# SQLite WAL is the correct mechanism for concurrent access (t-2085).
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR:-}" ]; then
    cd "$CLAUDE_PROJECT_DIR"
else
    cd "$HOME"
fi

mkdir -p "$HOME/.swarm"

DB_PATH="$HOME/.swarm/memory.db"
BACKUP_DIR="$HOME/.swarm/backups"
mkdir -p "$BACKUP_DIR"

# Integrity check: skip if another ruflo session has the DB open (WAL active),
# since concurrent WAL reads appear malformed to external sqlite3 connections.
# Only run integrity check when we're the sole opener (no .db-wal file present).
if [ -f "$DB_PATH" ] && [ ! -f "${DB_PATH}-wal" ]; then
    if ! sqlite3 "$DB_PATH" "PRAGMA integrity_check;" 2>/dev/null | grep -q "^ok$"; then
        echo "[ruflo-mcp] memory.db integrity check failed — recovering." >&2
        mv "$DB_PATH" "${DB_PATH}.corrupt-$(date +%Y-%m-%d)" 2>/dev/null || true
        # Restore the newest backup that PASSES integrity_check — not just the
        # newest. The backups carry corruption forward (the daily snapshot copies
        # whatever memory.db holds), so "restore newest" re-poisons the DB and
        # loops the corruption forward indefinitely (t-2236). Walk newest-first,
        # skipping any backup that is itself malformed.
        LATEST_BACKUP=""
        while IFS= read -r cand; do
            if sqlite3 "$cand" "PRAGMA integrity_check;" 2>/dev/null | grep -q "^ok$"; then
                LATEST_BACKUP="$cand"
                break
            fi
            echo "[ruflo-mcp] skipping corrupt backup: $cand" >&2
        done < <(ls -t "$BACKUP_DIR"/memory_*.db 2>/dev/null)
        if [ -n "$LATEST_BACKUP" ]; then
            cp "$LATEST_BACKUP" "$DB_PATH" && chmod 600 "$DB_PATH"
            echo "[ruflo-mcp] Restored from backup: $LATEST_BACKUP" >&2
        else
            echo "[ruflo-mcp] WARN: No healthy backup found — ruflo starts with empty DB." >&2
        fi
    fi
fi

# Daily backup: snapshot memory.db before ruflo opens it. Keep 14 days.
# Skip if another session has the DB open (WAL active) — the snapshot would be
# inconsistent without WAL merge. The backup-memory scheduler job covers this case.
TODAY="$(date +%Y%m%d)"
BACKUP_FILE="$BACKUP_DIR/memory_${TODAY}.db"
if [ -f "$DB_PATH" ] && [ ! -f "$BACKUP_FILE" ] && [ ! -f "${DB_PATH}-wal" ]; then
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
