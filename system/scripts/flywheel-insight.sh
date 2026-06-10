#!/usr/bin/env bash
# flywheel-insight.sh — the flywheel READ path (t-1937).
#
# 527 flywheel:* rows were computed at every session-end and never read
# (access_count=0 namespace-wide — architecture review 2026-06-10 §4: "the
# flywheel is observability theater"). This script closes the loop: find the
# project's two most recent flywheel rows, read them via the sanctioned
# `memory retrieve` (bumping access_count — the loop-closure metric), and
# emit ONE observation line for session-start to inject.
#
# Usage: flywheel-insight.sh <project> [db_path]
#   db_path defaults to ~/.swarm/memory.db (override for tests).
#
# Output: a single line, e.g.
#   correction_rate 0.30 (prev 0.10 ↑) · test_write_rate 0.20 · 12 edits, 0 failures last session
# Empty DB / no rows: prints "no prior session metrics for <project>", exit 0.

set -u

PROJECT="${1:?usage: flywheel-insight.sh <project> [db_path]}"
DB_PATH="${2:-$HOME/.swarm/memory.db}"

[ -f "$DB_PATH" ] || { echo "no prior session metrics for $PROJECT"; exit 0; }

# Key discovery only — read-only sqlite, ordered by recency. The actual row
# reads go through `memory retrieve` so access_count/last_accessed_at move.
KEYS=$(sqlite3 -readonly "$DB_PATH" \
    "SELECT key FROM memory_entries
     WHERE namespace='metrics' AND key LIKE 'flywheel:${PROJECT}:%' AND status='active'
     ORDER BY created_at DESC LIMIT 2;" 2>/dev/null) || KEYS=""

if [ -z "$KEYS" ]; then
    echo "no prior session metrics for $PROJECT"
    exit 0
fi

# Resolve the CLI entry (cf-env routes through ruflo-cli.sh since t-1936)
for _src in "$HOME/.claude/scripts/cf-env.sh" "$(dirname "$0")/cf-env.sh"; do
    [ -f "$_src" ] && source "$_src" && break
done
[ -n "${CF:-}" ] || { echo "no prior session metrics for $PROJECT (ruflo unavailable)"; exit 0; }

# Only the LATEST row needs the sanctioned read (that's the loop-closure
# signal — access_count moves). The prior row is trend garnish: read-only
# sqlite keeps this to ONE node startup so the session-start wait budget holds.
LATEST_KEY=$(echo "$KEYS" | head -1)
PRIOR_KEY=$(echo "$KEYS" | sed -n 2p)

LATEST_JSON=$(cd "$HOME" && timeout 8 $CF memory retrieve -k "$LATEST_KEY" --namespace metrics --value-only --path "$DB_PATH" 2>/dev/null) || LATEST_JSON=""
LATEST_JSON=$(echo "$LATEST_JSON" | sed -n '/^{/,$p' | head -1)

PRIOR_JSON=""
if [ -n "$PRIOR_KEY" ]; then
    PRIOR_JSON=$(sqlite3 -readonly "$DB_PATH" \
        "SELECT content FROM memory_entries WHERE namespace='metrics' AND key='$PRIOR_KEY';" 2>/dev/null | head -1) || PRIOR_JSON=""
fi

if [ -z "$LATEST_JSON" ]; then
    echo "no prior session metrics for $PROJECT (retrieve failed — see t-1937)"
    exit 0
fi

echo "$LATEST_JSON" | jq --arg prior "$PRIOR_JSON" -r '
    def num(x): (x // "0") | tostring | (try tonumber catch 0);
    . as $l
    | ($prior | try fromjson catch {}) as $p
    | num($l.correction_rate) as $cr
    | num($p.correction_rate) as $pcr
    | (if ($p | length) == 0 then ""
       elif $cr > $pcr then " (prev \($p.correction_rate) ↑)"
       elif $cr < $pcr then " (prev \($p.correction_rate) ↓)"
       else " (prev \($p.correction_rate) =)" end) as $trend
    | "correction_rate \($l.correction_rate // "?")\($trend) · test_write_rate \($l.test_write_rate // "?") · \($l.edits // 0) edits, \($l.failures // 0) failures last session"
' 2>/dev/null || echo "no prior session metrics for $PROJECT (parse failed)"
