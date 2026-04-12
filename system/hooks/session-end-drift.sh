#!/usr/bin/env bash
# session-end-drift.sh — Post-session system sync and cleanup.
#
# Input (env vars):
#   GIT_ROOT     repo root path
#   BRANA_CLI    path to brana binary (optional)
#   SCRIPT_DIR   directory of the calling script (for sync-state.sh resolution)
#   CORRECTIONS TEST_WRITES CASCADES EDITS  (for decisions.py log entry)
#
# Always exits 0 — sync/graph failures are non-fatal.

set +e

GIT_ROOT="${GIT_ROOT:-}"
BRANA_CLI="${BRANA_CLI:-}"
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
CORRECTIONS="${CORRECTIONS:-0}"
TEST_WRITES="${TEST_WRITES:-0}"
CASCADES="${CASCADES:-0}"
EDITS="${EDITS:-0}"

# ── sync-state push ───────────────────────────────────────────

SYNC_SCRIPT="$SCRIPT_DIR/../scripts/sync-state.sh"
if [ -x "$SYNC_SCRIPT" ] && [ -n "$GIT_ROOT" ] && [ -d "$GIT_ROOT" ]; then
    "$SYNC_SCRIPT" push 2>/dev/null || true
fi

# ── Spec graph rebuild ────────────────────────────────────────

if command -v brana &>/dev/null && [ -n "$GIT_ROOT" ] && [ -d "$GIT_ROOT" ]; then
    DOCS_CHANGED=$(git -C "$GIT_ROOT" diff --name-only HEAD~10..HEAD 2>/dev/null | \
        grep -cE '\.md$' || echo "0")
    if [ "$DOCS_CHANGED" -gt 0 ]; then
        brana graph build --output "$GIT_ROOT/docs/spec-graph.json" 2>/dev/null || true
    fi
elif [ -n "$BRANA_CLI" ] && [ -x "$BRANA_CLI" ] && [ -n "$GIT_ROOT" ] && [ -d "$GIT_ROOT" ]; then
    DOCS_CHANGED=$(git -C "$GIT_ROOT" diff --name-only HEAD~10..HEAD 2>/dev/null | \
        grep -cE '\.md$' || echo "0")
    if [ "$DOCS_CHANGED" -gt 0 ]; then
        "$BRANA_CLI" graph build --output "$GIT_ROOT/docs/spec-graph.json" 2>/dev/null || true
    fi
fi

# ── Decision log ──────────────────────────────────────────────

DECISIONS_PY="$SCRIPT_DIR/../scripts/decisions.py"
if [ -f "$DECISIONS_PY" ]; then
    SUMMARY="Session metrics: corrections=$CORRECTIONS, test_writes=$TEST_WRITES, cascades=$CASCADES, edits=$EDITS"
    uv run python3 "$DECISIONS_PY" log "session-end" "action" "$SUMMARY" \
        --severity "LOW" 2>/dev/null || true
fi

exit 0
