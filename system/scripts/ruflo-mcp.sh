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
# CORRECTION (t-2626): the WAL premise holds ONLY while the AgentDB bridge is
# up (native better-sqlite3). With the bridge down, ruflo silently falls back
# to sql.js — whole-file non-atomic writeFileSync, no WAL at all — which is
# what corrupted the store daily. The patch call below keeps the bridge up.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR:-}" ]; then
    cd "$CLAUDE_PROJECT_DIR"
else
    cd "$HOME"
fi

mkdir -p "$HOME/.swarm"

# t-2626: dedupe @claude-flow/memory's ControllerRegistry double-export before
# launch. The duplicate is an ESM SyntaxError that crashes the AgentDB bridge
# import and silently drops every memory op onto the sql.js whole-file-rewrite
# fallback — the root cause of the daily memory.db torn-write corruption. An
# npm upgrade/reinstall reverts the dist; re-asserting here self-heals on the
# next MCP launch. Never blocks startup.
"$(cd "$(dirname "$0")" && pwd)/patch-ruflo-memory-dup-export.sh" 2>&1 | head -2 >&2 || true

DB_PATH="$HOME/.swarm/memory.db"
BACKUP_DIR="$HOME/.swarm/backups"
mkdir -p "$BACKUP_DIR"

# Integrity check: a live -wal sidecar means another ruflo session may have the
# DB open, and checking the live file directly would false-positive (a
# mid-transaction read looks malformed to an external connection). Instead of
# skipping the check outright (t-2260 — that let real corruption through
# unchecked for 10 days since a -wal file is present most of the time), we
# checkpoint a COPY of the db+wal pair — never the live files — and check that.
ruflo_mcp_db_is_healthy() {
    local db="$1"
    if [ -f "${db}-wal" ]; then
        local tmpdir
        tmpdir=$(mktemp -d) || return 1
        # Use sqlite3's own .backup — it is atomic and WAL-aware. Copying db,
        # -wal and -shm as three separate `cp`s while a writer is live yields a
        # WAL that does not match the db snapshot; checkpointing that mismatched
        # pair manufactures corruption in the copy and condemns a healthy
        # database. That false positive is not theoretical: memory.db.corrupt-
        # 2026-07-31 and -2026-08-01 both pass integrity_check standalone, with
        # 4385 and 4332 rows — two intact databases discarded for nothing
        # (t-2619).
        local result err rc
        err=$(sqlite3 "$db" ".backup '$tmpdir/copy.db'" 2>&1); rc=$?
        if [ "$rc" -ne 0 ]; then
            rm -rf "$tmpdir"
            # WHY .backup can fail matters. A lock means another session is
            # writing — not evidence of corruption, and condemning on it is what
            # seeded the rotation loop. Anything else (malformed image, bad
            # header, read error) is exactly the corruption we must catch:
            # returning "healthy" there would reopen the t-2260 gap, where a
            # present -wal let real corruption through unchecked for 10 days.
            case "$err" in
                *locked*|*busy*|*BUSY*) return 0 ;;
                *)                      return 1 ;;
            esac
        fi
        result=$(sqlite3 "$tmpdir/copy.db" "PRAGMA integrity_check;" 2>/dev/null | tail -1)
        rm -rf "$tmpdir"
        [ "$result" = "ok" ]
        return
    fi
    sqlite3 "$db" "PRAGMA integrity_check;" 2>/dev/null | grep -q "^ok$"
}

# Rotate a condemned DB aside and restore the newest healthy backup.
#
# The sidecars are the whole story. Moving only memory.db leaves memory.db-wal
# and memory.db-shm behind; the restored backup is then opened underneath the
# orphaned WAL of the database that was just rotated away, SQLite replays it,
# and the fresh backup is malformed within milliseconds. The next session sees a
# broken DB and rotates again — a self-sustaining daily data-loss loop. Move the
# sidecars with the file they belong to, and make sure none remain before the
# restore (t-2619).
ruflo_mcp_recover_db() {
    local db="$1" backup_dir="$2"
    [ -f "$db" ] || return 0

    # NO flock here. A mutex was removed deliberately in t-2085 (its paired
    # orphan sweep killed live WAL writers and caused the corruption it meant to
    # prevent), and tests/scripts/test-ruflo-mcp-single-instance.sh enforces its
    # absence. Concurrency is mitigated lock-free instead:
    #   - this health re-check, so a session that lost the race does not rotate a
    #     database another session just restored;
    #   - `mv` for the rotation, which is atomic;
    #   - restore via temp-file + `mv`, so a half-copied DB is never visible.
    # Residual risk, stated rather than hidden: two sessions condemning within
    # the same instant can still both rotate. The window is small and both
    # outcomes leave a healthy DB, but it is not eliminated.
    if ruflo_mcp_db_is_healthy "$db"; then
        return 0
    fi

    local stamp; stamp="$(date +%Y-%m-%d)"
    local rotated="${db}.corrupt-${stamp}"
    # Never overwrite a previous rotation. This is not hypothetical: on
    # 2026-08-02 the DB rotated at 12:52 and again at 13:42, and the date-only
    # name meant the second rotation destroyed the first file and its salvage
    # dump — the only copies of five hours of writes. Keep the plain date for the
    # first rotation of the day (it is what operators and the integrity-gate test
    # look for) and disambiguate only on collision.
    if [ -e "$rotated" ] || [ -e "${rotated}.dump.sql" ]; then
        rotated="${db}.corrupt-$(date +%Y-%m-%d-%H%M%S)"
        [ -e "$rotated" ] && rotated="${rotated}-$$"
    fi

    # Secure the files BEFORE touching them. Opening the db to salvage would
    # checkpoint and delete its WAL, mutating a file we have not yet preserved —
    # and on a genuinely damaged db, writing to it can lose more than it saves.
    # Move first, then read from the rotated copy.
    local suffix
    for suffix in "" "-wal" "-shm"; do
        [ -e "${db}${suffix}" ] && mv "${db}${suffix}" "${rotated}${suffix}" 2>/dev/null
    done
    # Belt and braces: nothing stale may remain next to the restore target.
    rm -f "${db}-wal" "${db}-shm"

    # Salvage from the rotated copy. Even a malformed file usually yields most of
    # its rows — the 2026-08-02 file still dumps 1393 of them. `.recover` is not
    # compiled into sqlite3 3.50.6 here, so use `.dump`, which skips damaged
    # pages rather than refusing outright.
    sqlite3 "$rotated" ".dump" > "${rotated}.dump.sql" 2>/dev/null || true
    [ -s "${rotated}.dump.sql" ] || rm -f "${rotated}.dump.sql"

    # Restore the newest backup that PASSES integrity_check — not just the
    # newest. Backups carry corruption forward (the daily snapshot copies
    # whatever memory.db holds), so "restore newest" re-poisons the DB and loops
    # the corruption forward indefinitely (t-2236).
    local latest="" cand
    while IFS= read -r cand; do
        [ -n "$cand" ] || continue
        if sqlite3 "$cand" "PRAGMA integrity_check;" 2>/dev/null | grep -q "^ok$"; then
            latest="$cand"; break
        fi
        echo "[ruflo-mcp] skipping corrupt backup: $cand" >&2
    done < <(ls -t "$backup_dir"/memory_*.db 2>/dev/null)

    if [ -n "$latest" ]; then
        # temp + atomic mv: never expose a half-copied database to a session
        # that opens it mid-restore.
        local tmp="${db}.restore.$$"
        if cp "$latest" "$tmp" && chmod 600 "$tmp" && mv "$tmp" "$db"; then
            echo "[ruflo-mcp] Restored from backup: $latest" >&2
            return 0
        fi
        rm -f "$tmp"
        echo "[ruflo-mcp] WARN: restore from $latest failed." >&2
        return 1
    fi

    # No healthy backup: ruflo starts with an empty DB. Do NOT put the condemned
    # file back — running on a malformed database is worse than running on an
    # empty one, and restoring it in place is exactly the t-2260 loophole (a
    # corrupt DB left live because recovery declined to quarantine it).
    # Nothing is lost by quarantining: the data is preserved in the rotated file
    # and in the .dump.sql beside it, which is what the salvage step above is for.
    echo "[ruflo-mcp] WARN: no healthy backup — ruflo starts empty." >&2
    echo "[ruflo-mcp]       data preserved at: ${rotated}" >&2
    [ -f "${rotated}.dump.sql" ] && echo "[ruflo-mcp]       salvage dump: ${rotated}.dump.sql" >&2
    return 1
}

# Allow tests to source the functions above without running the wrapper.
[ -n "${RUFLO_MCP_SOURCE_ONLY:-}" ] && return 0

if [ -f "$DB_PATH" ]; then
    if ! ruflo_mcp_db_is_healthy "$DB_PATH"; then
        echo "[ruflo-mcp] memory.db integrity check failed — recovering." >&2
        ruflo_mcp_recover_db "$DB_PATH" "$BACKUP_DIR"
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

# Hardening (t-2755, 2026-08-12 upstream audit):
# - REQUIRE_REAL_EMBEDDINGS: the embedder silently falls back to deterministic
#   hash vectors when no ONNX model loads, degrading every search to noise with
#   no error. This makes the fallback throw instead (upstream v3.25.1).
# - SCAN_ON_WRITE: MemPoison/ChannelGuard injection scan before persisting to a
#   store that ingests agent output (memory store exits 2 on a finding —
#   hook callers already tolerate and log non-zero stores).
#   Kept unconditional here, unlike ruflo-cli.sh's default-if-unset form
#   (t-3097): this process is the long-lived MCP server, not spawned per call,
#   so there's no per-call caller to grant a scoped exemption to. The CLI path
#   (`brana knowledge process-url`, ruflo-cli.sh) needs the override because a
#   single Rust call site there ingests fetched content rather than
#   agent-authored memory and the scanner false-positives on it.
# - RUFLO_FUNNEL=0: kill switch for funnel telemetry, including the promo-message
#   fetch to funnel.ruv.io that is otherwise ON by default (opt-out upstream).
export RUFLO_REQUIRE_REAL_EMBEDDINGS=1
export RUFLO_MEMORY_SCAN_ON_WRITE=1
export RUFLO_FUNNEL=0

exec "$RUFLO" "$@"
