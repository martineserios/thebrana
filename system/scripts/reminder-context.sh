#!/usr/bin/env bash
# reminder-context.sh — session-start's pending-reminder line (t-1967/t-2116,
# ADR-051 §3). Prints the context string to stdout, or nothing.
#
# Extracted from session-start.sh in t-2988: that hook sits against the repo's
# 50KB file cap (validate.sh Check 8), so self-contained blocks now live here.
# Behaviour is unchanged.
#
# Usage: reminder-context.sh [brana-bin]

BRANA_BIN="${1:-}"
[ -n "$BRANA_BIN" ] && [ -x "$BRANA_BIN" ] || BRANA_BIN=$(command -v brana 2>/dev/null || true)

# Pending count: pure jq read — no Rust invocation (binary startup blows the
# <50ms budget), no transition writes. Count may be slightly stale (can include
# technically expired reminders) — accepted. Silent on missing/empty/corrupt
# store or 0. Past-due task links: also pure jq on store; one brana invocation
# per due+linked entry (rare) to look up task subject, timeout-bounded and
# guarded — degrades silently if the binary is absent.
REMINDER_CONTEXT=""
_REMINDER_STORE="$HOME/.claude/reminders.json"
if [ -s "$_REMINDER_STORE" ]; then
    _R_COUNTS=$(jq -r '[.reminders[]? | select(.status == "pending")] | "\(length) \([.[] | select(.priority == "high")] | length)"' "$_REMINDER_STORE" 2>/dev/null) || _R_COUNTS=""
    _R_PENDING="${_R_COUNTS%% *}"
    _R_HIGH="${_R_COUNTS##* }"
    if [ -n "$_R_PENDING" ] && [ "$_R_PENDING" -gt 0 ] 2>/dev/null; then
        REMINDER_CONTEXT="$_R_PENDING pending"
        [ "${_R_HIGH:-0}" -gt 0 ] 2>/dev/null && REMINDER_CONTEXT="$REMINDER_CONTEXT ($_R_HIGH high)"
        REMINDER_CONTEXT="$REMINDER_CONTEXT. brana remind list"
    fi
    # Past-due reminders linked to backlog tasks (t-2116)
    # Filter: pending, never dispatched, due field in the past, task_id set.
    # fromdateiso8601 parses RFC3339 → epoch seconds; now returns current epoch seconds.
    _DUE_LINKED=$(jq -r '
        [.reminders[]? |
            select(
                .status == "pending" and
                .dispatched_at == null and
                .due != null and
                (.due | fromdateiso8601) <= now and
                .task_id != null
            ) |
            "\(.id)\t\(.task_id)"
        ] | .[]
    ' "$_REMINDER_STORE" 2>/dev/null) || _DUE_LINKED=""
    if [ -n "$_DUE_LINKED" ]; then
        _BRANA_REM="$BRANA_BIN"
        while IFS=$'\t' read -r _RID _TID; do
            [ -z "$_RID" ] && continue
            _TSUBJECT=""
            if [ -n "$_BRANA_REM" ] && [ -x "$_BRANA_REM" ]; then
                _TSUBJECT=$(timeout -k 1 3 "$_BRANA_REM" backlog get "$_TID" 2>/dev/null \
                    | jq -r '.subject // empty' 2>/dev/null) || _TSUBJECT=""
            fi
            if [ -n "$_TSUBJECT" ]; then
                _REC="$_RID is past due — linked to $_TID '$_TSUBJECT': consider /brana:backlog start $_TID"
            else
                _REC="$_RID is past due — linked to $_TID: consider /brana:backlog start $_TID"
            fi
            REMINDER_CONTEXT="${REMINDER_CONTEXT:+$REMINDER_CONTEXT
}$_REC"
        done <<< "$_DUE_LINKED"
        unset _BRANA_REM _DUE_LINKED _RID _TID _TSUBJECT _REC
    fi
fi
unset _REMINDER_STORE _R_COUNTS _R_PENDING _R_HIGH


printf "%s" "$REMINDER_CONTEXT"
exit 0
