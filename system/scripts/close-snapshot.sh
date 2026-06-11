#!/usr/bin/env bash
# Track 1 close-instant: capture session diff snapshot + append to close queue
# (t-1973, ADR-052). Called by /brana:close for LIGHT and INSTANT closes.
#
# Usage:
#   close-snapshot.sh --git-root DIR --branch NAME --project SLUG --commit-count N
#
# Behavior:
#   - git diff HEAD~N..HEAD saved to ~/.claude/sessions/snap-{ts}.diff
#   - diff capped at 500KB (ADR-052 §4) — truncation sets --snapshot-truncated
#   - queue entry via `brana close-queue append` (Rust owns the store; no JSON here)
#   - degradation: missing brana binary or any capture failure → warn to
#     stderr, exit 0 — close NEVER blocks on the queue
#
# Exit codes: always 0 except for caller bugs (bad/missing arguments).

set -uo pipefail

MAX_SNAPSHOT_BYTES=512000  # 500KB cap per ADR-052 §4

GIT_ROOT="" BRANCH="" PROJECT="" COMMIT_COUNT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --git-root)     GIT_ROOT="$2"; shift 2 ;;
        --branch)       BRANCH="$2"; shift 2 ;;
        --project)      PROJECT="$2"; shift 2 ;;
        --commit-count) COMMIT_COUNT="$2"; shift 2 ;;
        *) echo "close-snapshot: unknown argument $1" >&2; exit 2 ;;
    esac
done

if [ -z "$GIT_ROOT" ] || [ -z "$BRANCH" ] || [ -z "$PROJECT" ] || [ -z "$COMMIT_COUNT" ]; then
    echo "close-snapshot: --git-root, --branch, --project, --commit-count are required" >&2
    exit 2
fi

# Nothing committed this session — nothing to extract, nothing to queue.
if [ "$COMMIT_COUNT" -le 0 ] 2>/dev/null; then
    exit 0
fi

# Resolve brana binary: $BRANA > sibling release build > PATH.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRANA_BIN="${BRANA:-}"
if [ -z "$BRANA_BIN" ] || [ ! -x "$BRANA_BIN" ]; then
    BRANA_BIN="$SCRIPT_DIR/../cli/rust/target/release/brana"
fi
if [ ! -x "$BRANA_BIN" ]; then
    BRANA_BIN="$(command -v brana 2>/dev/null)" || true
fi
if [ -z "$BRANA_BIN" ] || [ ! -x "$BRANA_BIN" ]; then
    echo "close-snapshot: brana binary not found — snapshot skipped, close continues" >&2
    exit 0
fi

# Capture the commit range. HEAD~N may not exist (shallow/short history) —
# fall back to the root commit.
GIT_RANGE=""
if git -C "$GIT_ROOT" rev-parse "HEAD~${COMMIT_COUNT}" >/dev/null 2>&1; then
    FROM=$(git -C "$GIT_ROOT" rev-parse --short "HEAD~${COMMIT_COUNT}" 2>/dev/null)
else
    FROM=$(git -C "$GIT_ROOT" rev-list --max-parents=0 HEAD 2>/dev/null | head -1 | cut -c1-7)
fi
TO=$(git -C "$GIT_ROOT" rev-parse --short HEAD 2>/dev/null)
if [ -z "$FROM" ] || [ -z "$TO" ]; then
    echo "close-snapshot: could not resolve commit range — snapshot skipped" >&2
    exit 0
fi
GIT_RANGE="${FROM}..${TO}"

SESS_DIR="$HOME/.claude/sessions"
mkdir -p "$SESS_DIR"
TS=$(date +%Y%m%d-%H%M%S)
SNAP_FILE="$SESS_DIR/snap-${TS}-$$.diff"

if ! git -C "$GIT_ROOT" diff "$GIT_RANGE" > "$SNAP_FILE" 2>/dev/null; then
    echo "close-snapshot: git diff failed — snapshot skipped" >&2
    rm -f "$SNAP_FILE"
    exit 0
fi

# Cap at 500KB (ADR-052 §4): truncate and flag.
TRUNCATED_FLAG=""
SNAP_SIZE=$(stat -c %s "$SNAP_FILE" 2>/dev/null || echo 0)
if [ "$SNAP_SIZE" -gt "$MAX_SNAPSHOT_BYTES" ]; then
    truncate -s "$MAX_SNAPSHOT_BYTES" "$SNAP_FILE" 2>/dev/null || {
        head -c "$MAX_SNAPSHOT_BYTES" "$SNAP_FILE" > "${SNAP_FILE}.tmp" && mv "${SNAP_FILE}.tmp" "$SNAP_FILE"
    }
    TRUNCATED_FLAG="--snapshot-truncated"
fi

if ! "$BRANA_BIN" close-queue append \
    --project "$PROJECT" \
    --branch "$BRANCH" \
    --git-root "$GIT_ROOT" \
    --git-range "$GIT_RANGE" \
    --snapshot-path "$SNAP_FILE" \
    --commit-count "$COMMIT_COUNT" \
    ${TRUNCATED_FLAG:+$TRUNCATED_FLAG} >/dev/null; then
    echo "close-snapshot: queue append failed — snapshot saved at $SNAP_FILE, close continues" >&2
    exit 0
fi

echo "queued: $GIT_RANGE → $SNAP_FILE${TRUNCATED_FLAG:+ (truncated)}"
exit 0
