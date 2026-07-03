#!/usr/bin/env bash
# Track 1 close-instant: capture session diff snapshot + append to close queue
# (t-1973, ADR-052). Called by /brana:close for LIGHT and INSTANT closes.
#
# Usage:
#   close-snapshot.sh --git-root DIR --branch NAME --project SLUG --commit-count N \
#                     [--git-range A..B]
#
# Behavior:
#   - session diff saved to ~/.claude/sessions/snap-{ts}.diff. The range is
#     --git-range verbatim when given (PREFERRED — t-2242); otherwise derived
#     as HEAD~N..HEAD. The HEAD~N fallback is WRONG whenever a --no-ff merge
#     sits inside the window: the caller's commit count is topological while
#     HEAD~N walks first-parent only, so the range over-reaches and swallows
#     a concurrent session's commits (two live hits, proyecto_anita 2026-07-02).
#     Callers should always pass --git-range anchored on real SHAs.
#   - diff capped at 500KB (ADR-052 §4) — truncation sets --snapshot-truncated
#   - queue entry via `brana close-queue append` (Rust owns the store; no JSON here)
#   - degradation: missing brana binary or any capture failure → warn to
#     stderr, exit 0 — close NEVER blocks on the queue
#
# Exit codes: always 0 except for caller bugs (bad/missing arguments).

set -uo pipefail

MAX_SNAPSHOT_BYTES=512000  # 500KB cap per ADR-052 §4

GIT_ROOT="" BRANCH="" PROJECT="" COMMIT_COUNT="" GIT_RANGE_ARG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --git-root)     GIT_ROOT="$2"; shift 2 ;;
        --branch)       BRANCH="$2"; shift 2 ;;
        --project)      PROJECT="$2"; shift 2 ;;
        --commit-count) COMMIT_COUNT="$2"; shift 2 ;;
        --git-range)    GIT_RANGE_ARG="$2"; shift 2 ;;
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

# Capture the commit range.
GIT_RANGE=""
if [ -n "$GIT_RANGE_ARG" ]; then
    # Explicit range from the caller (t-2242) — validate both endpoints so an
    # unresolvable range degrades to a skipped snapshot instead of queueing a
    # diff that git silently produced against garbage.
    R_FROM="${GIT_RANGE_ARG%%..*}"
    R_TO="${GIT_RANGE_ARG##*..}"
    if ! git -C "$GIT_ROOT" rev-parse -q --verify "${R_FROM}^{commit}" >/dev/null 2>&1 \
       || ! git -C "$GIT_ROOT" rev-parse -q --verify "${R_TO}^{commit}" >/dev/null 2>&1; then
        echo "close-snapshot: --git-range '$GIT_RANGE_ARG' does not resolve — snapshot skipped" >&2
        exit 0
    fi
    GIT_RANGE="$GIT_RANGE_ARG"
else
    # Legacy fallback: HEAD~N anchoring. KNOWN-WRONG across --no-ff merges
    # (first-parent walk vs the caller's topological count) — kept only for
    # callers that cannot compute a range. HEAD~N may also not exist
    # (shallow/short history) — fall back to the root commit.
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
fi

SESS_DIR="$HOME/.claude/sessions"
mkdir -p "$SESS_DIR"
TS=$(date +%Y%m%d-%H%M%S)
SNAP_FILE="$SESS_DIR/snap-${TS}-$$.diff"

if ! git -C "$GIT_ROOT" diff "$GIT_RANGE" > "$SNAP_FILE" 2>/dev/null; then
    echo "close-snapshot: git diff failed — snapshot skipped" >&2
    rm -f "$SNAP_FILE"
    exit 0
fi

# Cap at 500KB (ADR-052 §4): cut at the last whole diff --git boundary before
# the cap so no hunk is split mid-content. Record dropped file names.
TRUNCATED_FLAG=""
OMITTED_ARRAY=()
SNAP_SIZE=$(stat -c %s "$SNAP_FILE" 2>/dev/null || echo 0)
if [ "$SNAP_SIZE" -gt "$MAX_SNAPSHOT_BYTES" ]; then
    # Find byte offset of the last "\ndiff --git " header that starts before the cap.
    # grep -b emits "OFFSET:match" for each hit; tail -1 picks the last one.
    CUT_OFFSET=$(head -c "$MAX_SNAPSHOT_BYTES" "$SNAP_FILE" \
        | grep -bo $'\ndiff --git ' 2>/dev/null | tail -1 | cut -d: -f1)
    CUT_OFFSET="${CUT_OFFSET:-0}"
    # Collect omitted files: all "diff --git a/FILE b/FILE" headers after CUT_OFFSET.
    # tail -c +N is 1-based, so add 1. sed extracts the b/ filename.
    OMITTED=$(tail -c +"$((CUT_OFFSET + 1))" "$SNAP_FILE" \
        | grep '^diff --git ' \
        | sed 's|^diff --git a/.* b/||' \
        | awk '!seen[$0]++')
    # Truncate at the hunk boundary.
    if [ "${CUT_OFFSET:-0}" -gt 0 ] && [ "$CUT_OFFSET" -lt "$SNAP_SIZE" ]; then
        head -c "$CUT_OFFSET" "$SNAP_FILE" > "${SNAP_FILE}.tmp" && mv "${SNAP_FILE}.tmp" "$SNAP_FILE"
    else
        head -c "$MAX_SNAPSHOT_BYTES" "$SNAP_FILE" > "${SNAP_FILE}.tmp" && mv "${SNAP_FILE}.tmp" "$SNAP_FILE"
    fi
    TRUNCATED_FLAG="--snapshot-truncated"
    # Build repeatable --omitted-files flags for the queue append (array to
    # handle filenames with spaces — word-split-safe).
    if [ -n "$OMITTED" ]; then
        while IFS= read -r omf; do
            [ -n "$omf" ] && OMITTED_ARRAY+=("--omitted-files" "$omf")
        done <<< "$OMITTED"
    fi
fi

# --propagate on EVERY queued close (ADR-056 §4 fail-safe): at snapshot time
# (Step 1b) the in-session L2 audit hasn't run yet and may fail — Step 8b
# clears the flag via `close-queue mark-propagated` only on L2 success.
if ! "$BRANA_BIN" close-queue append \
    --project "$PROJECT" \
    --branch "$BRANCH" \
    --git-root "$GIT_ROOT" \
    --git-range "$GIT_RANGE" \
    --snapshot-path "$SNAP_FILE" \
    --commit-count "$COMMIT_COUNT" \
    --propagate \
    ${TRUNCATED_FLAG:+$TRUNCATED_FLAG} \
    "${OMITTED_ARRAY[@]}" >/dev/null; then
    echo "close-snapshot: queue append failed — snapshot saved at $SNAP_FILE, close continues" >&2
    exit 0
fi

echo "queued: $GIT_RANGE → $SNAP_FILE${TRUNCATED_FLAG:+ (truncated)}"
exit 0
