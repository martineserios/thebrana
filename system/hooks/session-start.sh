#!/usr/bin/env bash
# No strict mode — hooks must always return valid JSON.

# Brana SessionStart hook — recall relevant patterns at session start.
# Input:  stdin JSON (session_id, cwd, hook_event_name, matcher)
# Output: stdout JSON with additionalContext field
#
# Strategy: run fast local checks synchronously, launch 1 ruflo query
# in parallel (2s timeout), collect results, emit JSON. Fork logging
# to background after response. Timing marks in /tmp/brana-startup-timing.log.

# Ensure valid CWD
cd /tmp 2>/dev/null || true

# ── Startup timing (diagnostic) ─────────────────────────
_TIMING_LOG="/tmp/brana-startup-timing.log"
_ts() { echo $(( $(date +%s) * 1000 )); }
_mark() { echo "[brana-diag] $1 $(_ts)" >> "$_TIMING_LOG" 2>/dev/null || true; }
_mark "hook-start"

INPUT=$(cat) || true
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true
SESSION_ID="${SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || true
EFFORT_LEVEL=$(echo "$INPUT" | jq -r '.effort.level // "normal"' 2>/dev/null) || EFFORT_LEVEL="normal"

if [ -z "${SESSION_ID:-}" ] || [ -z "${CWD:-}" ]; then
    echo '{"continue": true}'
    exit 0
fi

# Derive project name from git root or cwd
GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "$CWD")
PROJECT=$(basename "$GIT_ROOT")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source profile library for effort level
source "$SCRIPT_DIR/lib/profile.sh" 2>/dev/null || true

# Write env vars for downstream hooks if CLAUDE_ENV_FILE exists
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "BRANA_PROJECT=$PROJECT" >> "$CLAUDE_ENV_FILE"
    echo "BRANA_SESSION_ID=$SESSION_ID" >> "$CLAUDE_ENV_FILE"
    EFFORT=$(get_profile_effort 2>/dev/null || echo "high")
    echo "BRANA_EFFORT_LEVEL=$EFFORT" >> "$CLAUDE_ENV_FILE"
fi

# ── Reset session score counter ──────────────────────────
printf '0\t0\n' > "$HOME/.claude/session-score.tsv" 2>/dev/null || true

# ── Temp files for parallel results ───────────────────────
TMPDIR_SS="/tmp/brana-ss-${SESSION_ID}"
mkdir -p "$TMPDIR_SS" 2>/dev/null || true
trap 'rm -rf "$TMPDIR_SS"' EXIT

# ── Source cf-env.sh ──────────────────────────────────────
if [ -f "$SCRIPT_DIR/lib/cf-env.sh" ]; then
    source "$SCRIPT_DIR/lib/cf-env.sh"
else
    source "$HOME/.claude/scripts/cf-env.sh"
fi

# ── Sync brana binary to PLUGIN_DATA ─────────────────────────
# PLUGIN_DATA survives plugin updates. Copy the binary there so hooks
# always find it, even after a plugin cache wipe.
if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
    mkdir -p "$CLAUDE_PLUGIN_DATA" 2>/dev/null || true
    SRC_BIN="${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/..}/cli/rust/target/release/brana"
    DST_BIN="${CLAUDE_PLUGIN_DATA}/brana"
    if [ -x "$SRC_BIN" ]; then
        if [ ! -x "$DST_BIN" ] || [ "$SRC_BIN" -nt "$DST_BIN" ]; then
            cp "$SRC_BIN" "$DST_BIN" 2>/dev/null || true
            # Invalidate skills mtime marker — plugin updated, skills may have changed
            rm -f /tmp/brana-skills-index-mtime 2>/dev/null || true
        fi
    fi
    # Also sync brana-query if it exists
    SRC_Q="${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/..}/cli/rust/target/release/brana-query"
    DST_Q="${CLAUDE_PLUGIN_DATA}/brana-query"
    if [ -x "$SRC_Q" ]; then
        if [ ! -x "$DST_Q" ] || [ "$SRC_Q" -nt "$DST_Q" ]; then
            cp "$SRC_Q" "$DST_Q" 2>/dev/null || true
        fi
    fi
fi

# ── /tmp space check ───────────────────────────────────────
# CC sandbox (/tmp/claude-*) grows unbounded and can fill tmpfs.
# Warn early so the user can act before all shell commands fail.
TMP_WARNING=""
TMP_USE_PCT=$(df /tmp 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}') || true
if [ -n "$TMP_USE_PCT" ] && [ "$TMP_USE_PCT" -ge 80 ] 2>/dev/null; then
    TMP_AVAIL=$(df -h /tmp 2>/dev/null | awk 'NR==2 {print $4}') || TMP_AVAIL="unknown"
    TMP_WARNING="⚠ /tmp is ${TMP_USE_PCT}% full (${TMP_AVAIL} free). CC sandbox files may fill it — clean stale sessions manually if needed: du -sh /tmp/claude-* | sort -rh"
fi

# ── Loud failures (t-1938): surface what last session swallowed ──────────
# 1. Memory persist failures logged by session-end-persist.sh
RUN_STATE_DIR="${BRANA_RUN_STATE_DIR:-$HOME/.claude/run-state}"
PERSIST_FAIL_CONTEXT=""
PF_LOG="$RUN_STATE_DIR/persist-failures.log"
if [ -s "$PF_LOG" ]; then
    PF_COUNT=$(wc -l < "$PF_LOG" 2>/dev/null | tr -d ' ') || PF_COUNT="?"
    PF_LAST=$(tail -1 "$PF_LOG" 2>/dev/null) || PF_LAST=""
    PERSIST_FAIL_CONTEXT="⚠ [Memory persist] $PF_COUNT failed memory write(s) since last surfaced — most recent: $PF_LAST. The learning loop lost data; check ruflo health (brana doctor)."
    # rotate: keep forensics, clear the active log so this surfaces once
    cat "$PF_LOG" >> "${PF_LOG}.surfaced" 2>/dev/null || true
    : > "$PF_LOG" 2>/dev/null || true
fi

# 2. Scheduler job failures (review §4: feed-ruflo-index failed 2 days unnoticed)
SCHED_STATUS="${BRANA_SCHED_STATUS:-$HOME/.claude/scheduler/last-status.json}"
SCHED_FAIL_CONTEXT=""
if [ -f "$SCHED_STATUS" ]; then
    SCHED_FAILS_ALL=$(jq -r 'to_entries[] | select(.value.status != null and (.value.status | test("SUCCESS|SKIPPED") | not)) | "\(.key) (\(.value.status), \(.value.timestamp // "?"))"' "$SCHED_STATUS" 2>/dev/null) || SCHED_FAILS_ALL=""
    if [ -n "$SCHED_FAILS_ALL" ]; then
        SCHED_FAIL_TOTAL=$(echo "$SCHED_FAILS_ALL" | wc -l | tr -d ' ')
        SCHED_FAILS=$(echo "$SCHED_FAILS_ALL" | head -3)
        SCHED_MORE=""
        [ "$SCHED_FAIL_TOTAL" -gt 3 ] 2>/dev/null && SCHED_MORE=" (+$((SCHED_FAIL_TOTAL - 3)) more — brana ops status)"
        SCHED_FAIL_CONTEXT="⚠ [Scheduler] failing job(s): $(echo "$SCHED_FAILS" | tr '\n' ';' | sed 's/;$//')${SCHED_MORE}. Check: brana ops logs <job>."
    fi
fi

# 3. Close-queue dead-man check (t-1979 disposition #1, challenger 3/3 quorum).
# Pure jq, read-only — deliberately independent of the brana binary: a dead
# cron, a missing binary, and an unregistered job all manifest as a stale
# queue, and the monitor must not depend on the thing it monitors.
CQ_STALE_CONTEXT=""
CQ_FILE="$HOME/.claude/close-queue.json"
if [ -f "$CQ_FILE" ]; then
    CQ_CUTOFF=$(date -u -d '3 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || CQ_CUTOFF=""
    if [ -n "$CQ_CUTOFF" ]; then
        # RFC3339 UTC timestamps compare correctly as strings at day granularity
        CQ_STALE=$(jq -r --arg cutoff "$CQ_CUTOFF" \
            '[.entries[]? | select((.processed // false) | not) | select(.timestamp < $cutoff)] | length' \
            "$CQ_FILE" 2>/dev/null) || CQ_STALE=0
        if [ "${CQ_STALE:-0}" -gt 0 ] 2>/dev/null; then
            CQ_STALE_CONTEXT="⚠ [Close queue] $CQ_STALE entr(ies) unprocessed >3 days — extraction cron dead, binary missing, or job unregistered. Check: brana ops logs close-extraction && brana close-queue list --unprocessed"
        fi
    fi
fi

# ══════════════════════════════════════════════════════════
# PHASE 1: Launch slow operations in parallel
# ══════════════════════════════════════════════════════════
_mark "phase1-start"

CF_WARNING=""
PIDS=""

# Job 1: ruflo memory search (patterns + corrections in single query)
# Skip on low effort — 2s network query is non-critical for quick tasks.
if [ -n "$CF" ] && [ "${EFFORT_LEVEL:-normal}" != "low" ]; then
    (
        # Namespace-scoped recall (t-1936): the old namespace-less "client:$PROJECT"
        # query returned only constant-0.5 session rows, which the jq filters below
        # discarded — recall was empty every session. The pattern namespace excludes
        # session rows structurally; 0.3 matches the build LOAD threshold. Timeout
        # raised 2s→8s: ONNX model load alone takes ~1.6s, search ~2s total.
        CF_OUTPUT=$(cd "$HOME" && timeout 8 $CF memory search --query "$PROJECT build patterns corrections learnings" --namespace pattern --threshold 0.3 --limit 5 --format json 2>&1)
        CF_EXIT=$?   # captured BEFORE any || true — was dead code reading 0 forever
        # CLI emits ONNX/INFO noise before the JSON object — keep JSON only.
        CF_JSON=$(echo "$CF_OUTPUT" | sed -n '/^{/,$p')
        # Format as readable lines; output shape is {results: [{key, score, preview}]}
        CONTEXT=$(echo "$CF_JSON" | jq -r '.results[]? | "- \(.key) (score \(.score * 100 | floor / 100)): \(.preview)"' 2>/dev/null) || CONTEXT=""
        if [ $CF_EXIT -eq 124 ]; then
            echo "TIMEOUT" > "$TMPDIR_SS/cf-warning"
        elif [ -z "$CF_JSON" ]; then
            # No JSON at all — invocation failed (loud, not silent: see t-1936/t-1938)
            echo "FAILED" > "$TMPDIR_SS/cf-warning"
        fi
        echo "$CONTEXT" > "$TMPDIR_SS/cf-context"
        # Extract corrections from same result (correction-keyed entries)
        CP_LINES=$(echo "$CF_JSON" | jq -r '.results[]? | select(.key | test("correction"; "i")) | (.key + ": " + .preview)' 2>/dev/null | head -3) || CP_LINES=""
        if [ -n "$CP_LINES" ]; then
            echo "$CP_LINES" > "$TMPDIR_SS/corrections"
        fi
        # Store recalled pattern keys for promotion tracking (t-203).
        # Everything returned is a pattern-namespace hit — collect all keys.
        RECALLED_KEYS=$(echo "$CF_JSON" | jq -c '[.results[]?.key] // []' 2>/dev/null) || RECALLED_KEYS="[]"
        echo "$RECALLED_KEYS" > "$TMPDIR_SS/recalled-keys"
    ) &
    PIDS="$PIDS $!"
else
    CF_WARNING="ruflo not found. Memory recall unavailable. Install: npm i -g ruflo"
    echo "" > "$TMPDIR_SS/cf-context"
fi

# Job 1b: flywheel insight — read last session's metrics, surface one
# observation (t-1937). This is the flywheel READ path: before it, 527
# flywheel:* rows had access_count=0 (computed every session-end, never read).
if [ "${EFFORT_LEVEL:-normal}" != "low" ]; then
    (
        FW_SCRIPT=""
        for _fw in "$HOME/.claude/scripts/flywheel-insight.sh" "${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR/..}/scripts/flywheel-insight.sh"; do
            [ -x "$_fw" ] && FW_SCRIPT="$_fw" && break
        done
        if [ -n "$FW_SCRIPT" ]; then
            timeout 12 bash "$FW_SCRIPT" "$PROJECT" > "$TMPDIR_SS/flywheel-insight" 2>/dev/null || true
        fi
    ) &
    PIDS="$PIDS $!"
fi

# Job 1c: hybrid recall (FTS5 + ruflo via brana recall / HybridProvider, ADR-058)
# Additive to Job 1 — independent stores (ADR-058 §store-independence-invariant):
#   FTS5 indexes ~/.claude/memory/*.md; ruflo indexes knowledge entries via vector DB.
# Does NOT require ruflo ($CF) — degrades to FTS5-only when ruflo is unavailable.
# Skip on low effort — interactive recall budget is non-critical for quick tasks.
if [ "${EFFORT_LEVEL:-normal}" != "low" ]; then
    (
        BRANA_RECALL=""
        if [ -n "${CLAUDE_PLUGIN_DATA:-}" ] && [ -x "${CLAUDE_PLUGIN_DATA}/brana" ]; then
            BRANA_RECALL="${CLAUDE_PLUGIN_DATA}/brana"
        fi
        if [ -z "$BRANA_RECALL" ]; then
            BRANA_RECALL=$(command -v brana 2>/dev/null || true)
        fi
        if [ -n "$BRANA_RECALL" ] && [ -x "$BRANA_RECALL" ]; then
            RECALL_RAW=$(cd "$GIT_ROOT" && timeout 3 "$BRANA_RECALL" recall \
                "$PROJECT build patterns corrections learnings" \
                --top 5 --json 2>/dev/null) || RECALL_RAW=""
            if [ -n "$RECALL_RAW" ]; then
                RECALL_LINES=$(echo "$RECALL_RAW" | jq -r \
                    '.[] | (.doc.MemoryFile.slug // .doc.KnowledgeEntry.key // "?") as $k |
                     "- \($k): \(.snippet | gsub("\n"; " ") | .[0:120])"' \
                    2>/dev/null) || RECALL_LINES=""
                [ -n "$RECALL_LINES" ] && echo "$RECALL_LINES" > "$TMPDIR_SS/hybrid-recall"
            fi
        fi
    ) &
    # Not added to PIDS — the PIDS kill loop has a timing issue where
    # date +%s%3N gives nanoseconds on Linux, making REMAINING_MS always
    # negative and killing jobs before they write their results. Recall
    # is waited on separately in Phase 3 with a proper 3s wall-clock guard.
    RECALL_PID="$!"
fi

# ══════════════════════════════════════════════════════════
# PHASE 2: Fast local checks (while parallel jobs run)
# ══════════════════════════════════════════════════════════
_mark "phase2-start"

# ── Stale file claim cleanup ─────────────────────────────
find /tmp/brana-claims -name "ts" -mmin +60 2>/dev/null | while read f; do
    rm -rf "$(dirname "$f")"
done

# ── Stale ruflo MCP lock detection (t-1921) ──────────────
# If the ruflo server died without cleanup, it leaves stale lock+pid files.
# The next startup sees the lock, skips restart, and all mcp__ruflo__* calls
# return -32000. Fix: remove the lock when the recorded PID is no longer alive.
RUFLO_LOCK="$HOME/.swarm/ruflo-mcp.lock"
RUFLO_PID_FILE="$HOME/.swarm/ruflo-mcp.pid"
if [ -f "$RUFLO_LOCK" ]; then
    _RUFLO_PID=$(cat "$RUFLO_PID_FILE" 2>/dev/null | tr -dc '0-9') || true
    if [ -z "$_RUFLO_PID" ] || ! kill -0 "$_RUFLO_PID" 2>/dev/null; then
        rm -f "$RUFLO_LOCK" 2>/dev/null || true
    fi
    unset _RUFLO_PID
fi

# ── Extra-usage disabled warning (t-1034) ────────────────
# CC caches extra-usage state in ~/.claude.json. If it's disabled,
# 1M-context models fail around the 200k-token mark with an
# "Extra usage is required for 1M context" API error mid-skill.
# Brana can't toggle billing, but it can warn loudly at session start
# so the user switches model before invoking heavy skills.
# Silence with: BRANA_1M_WARN_OFF=1
EU_WARNING=""
if [ -z "${BRANA_1M_WARN_OFF:-}" ] && [ -f "$HOME/.claude.json" ]; then
    EU_REASON=$(jq -r '.cachedExtraUsageDisabledReason // empty' "$HOME/.claude.json" 2>/dev/null) || EU_REASON=""
    if [ -n "$EU_REASON" ]; then
        EU_WARNING="Extra-usage disabled (${EU_REASON}). 1M-context models will fail around the 200k-token mark with an API error mid-skill. Run /model to switch to standard Opus 4.7 or Sonnet 4.6 before invoking /brana:close or other heavy skills. Silence: BRANA_1M_WARN_OFF=1"
    fi
fi

# ── Lint-heal gate check (t-1075) ────────────────────────
# Gate: surface reminder if >7d since last run AND >=5 sessions since last run.
# Always increment session_count_since_run regardless.
LINT_HEAL_CONTEXT=""
LINT_HEAL_STATE="$HOME/.swarm/lint-heal-state.json"
if [ -f "$LINT_HEAL_STATE" ]; then
    LH_LAST_RUN=$(jq -r '.last_run_ts // 0' "$LINT_HEAL_STATE" 2>/dev/null) || LH_LAST_RUN=0
    LH_SESSION_COUNT=$(jq -r '.session_count_since_run // 0' "$LINT_HEAL_STATE" 2>/dev/null) || LH_SESSION_COUNT=0
    NOW_S=$(date +%s 2>/dev/null || echo 0)
    SEVEN_DAYS=604800
    if [ "$(( NOW_S - LH_LAST_RUN ))" -ge "$SEVEN_DAYS" ] && [ "$LH_SESSION_COUNT" -ge 5 ] 2>/dev/null; then
        DAYS_SINCE=$(( (NOW_S - LH_LAST_RUN) / 86400 ))
        LINT_HEAL_CONTEXT="Lint+Heal due (${DAYS_SINCE}d since last run, ${LH_SESSION_COUNT} sessions). Run: brana memory lint-heal --dry-run"
    fi
    # Increment session counter
    NEW_LH_COUNT=$(( LH_SESSION_COUNT + 1 ))
    jq --argjson c "$NEW_LH_COUNT" '.session_count_since_run = $c' "$LINT_HEAL_STATE" > "${LINT_HEAL_STATE}.tmp" 2>/dev/null \
        && mv "${LINT_HEAL_STATE}.tmp" "$LINT_HEAL_STATE" 2>/dev/null || true
fi

# ── Config drift detection ─────────────────────────────
DRIFT_CONTEXT=""
DRIFT_SCRIPT="$SCRIPT_DIR/config-drift.sh"
if [ -f "$DRIFT_SCRIPT" ]; then
    DRIFT_JSON=$(bash "$DRIFT_SCRIPT" </dev/null 2>/dev/null) || true
    DRIFT_STATUS=$(echo "$DRIFT_JSON" | jq -r '.status // empty' 2>/dev/null) || true
    if [ "$DRIFT_STATUS" = "drifted" ]; then
        DRIFT_COUNT=$(echo "$DRIFT_JSON" | jq -r '.count' 2>/dev/null) || DRIFT_COUNT=0
        DRIFT_FILES=$(echo "$DRIFT_JSON" | jq -r '.drifted[] | "\(.type): \(.file)"' 2>/dev/null | head -10) || DRIFT_FILES=""
        MCP_COUNT=$(echo "$DRIFT_JSON" | jq -r '.mcp_count // 0' 2>/dev/null) || MCP_COUNT=0
        MCP_LINES=$(echo "$DRIFT_JSON" | jq -r '.mcp_violations[]? // empty' 2>/dev/null | head -5) || MCP_LINES=""

        DRIFT_CONTEXT=""
        if [ "$DRIFT_COUNT" -gt 0 ]; then
            DRIFT_CONTEXT="Config drift detected ($DRIFT_COUNT files). Re-run bootstrap.sh to sync:
$DRIFT_FILES"
        fi
        if [ "$MCP_COUNT" -gt 0 ]; then
            MCP_MSG="[ADR-033] $MCP_COUNT npx/uvx MCP server(s) in ~/.claude.json — pin to binary paths:
$MCP_LINES"
            DRIFT_CONTEXT="${DRIFT_CONTEXT:+$DRIFT_CONTEXT
}$MCP_MSG"
        fi
    fi
fi

# ── Bootstrap restart sentinel ───────────────────────────
SENTINEL_WARNING=""
SENTINEL_FILE="/tmp/brana-bootstrap-pending-restart"
if [ -f "$SENTINEL_FILE" ]; then
    SENTINEL_WARNING="Previous bootstrap changed hooks — restart CC to activate."
    rm -f "$SENTINEL_FILE" 2>/dev/null || true
fi

# ── Stale binary detection ────────────────────────────────
STALE_BINARY_WARNING=""
_BRANA_BIN=$(command -v brana 2>/dev/null) || true
if [ -n "${_BRANA_BIN:-}" ] && [ -x "$_BRANA_BIN" ]; then
    _BIN_MTIME=$(stat -c %Y "$_BRANA_BIN" 2>/dev/null) || _BIN_MTIME=0
    _LAST_CLI_CT=$(git -C "$GIT_ROOT" log --format="%ct" -1 -- system/cli/ 2>/dev/null) || _LAST_CLI_CT=""
    if [ -n "$_LAST_CLI_CT" ] && [ "${_BIN_MTIME:-0}" -lt "$_LAST_CLI_CT" ]; then
        _BIN_DATE=$(date -d "@$_BIN_MTIME" "+%Y-%m-%d %H:%M" 2>/dev/null) || _BIN_DATE="unknown"
        _COMMIT_DATE=$(date -d "@$_LAST_CLI_CT" "+%Y-%m-%d %H:%M" 2>/dev/null) || _COMMIT_DATE="unknown"
        STALE_BINARY_WARNING="brana binary (built $_BIN_DATE) predates last system/cli commit ($_COMMIT_DATE). Rebuild: cd system/cli/rust && cargo build --release"
    fi
fi
unset _BRANA_BIN _BIN_MTIME _LAST_CLI_CT _BIN_DATE _COMMIT_DATE

# ── Pending reminder count + past-due task links (t-1967/t-2116, ADR-051 §3) ──
# Pending count: pure jq read — no Rust invocation (binary startup blows the
# <50ms budget), no transition writes. Count may be slightly stale (can include
# technically expired reminders) — accepted. Silent on missing/empty/corrupt store or 0.
# Past-due task links: also pure jq on store; one brana invocation per due+linked
# entry (rare) to look up task subject. Guarded — degrades silently if binary absent.
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
        _BRANA_REM="${BRANA_BIN:-$(command -v brana 2>/dev/null || true)}"
        while IFS=$'\t' read -r _RID _TID; do
            [ -z "$_RID" ] && continue
            _TSUBJECT=""
            if [ -n "$_BRANA_REM" ] && [ -x "$_BRANA_REM" ]; then
                _TSUBJECT=$("$_BRANA_REM" backlog get "$_TID" 2>/dev/null \
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

# ── Daily extraction summary (t-1975, ADR-052) ────────────
# Pure read of the newest of today's/yesterday's daily-summary file (the
# 2am cron writes today's date). Silent when absent or empty.
YESTERDAY_CONTEXT=""
_DS_FILE="$HOME/.claude/sessions/daily-summary-$(date +%F).md"
[ -s "$_DS_FILE" ] || _DS_FILE="$HOME/.claude/sessions/daily-summary-$(date -d yesterday +%F 2>/dev/null).md"
if [ -s "$_DS_FILE" ]; then
    _DS_LEARN=$(grep -c '^- \[' "$_DS_FILE" 2>/dev/null) || _DS_LEARN=0
    if [ "${_DS_LEARN:-0}" -gt 0 ] 2>/dev/null; then
        YESTERDAY_CONTEXT="$_DS_LEARN learning(s) extracted overnight. Review: $_DS_FILE"
    else
        YESTERDAY_CONTEXT="extraction ran, nothing notable. $_DS_FILE"
    fi
fi
unset _DS_FILE _DS_LEARN

# ── Task context injection ──────────────────────────────
TASK_CONTEXT=""
TASKS_FILE=""

if [ -d "$GIT_ROOT/.claude" ] && [ -f "$GIT_ROOT/.claude/tasks.json" ]; then
    TASKS_FILE="$GIT_ROOT/.claude/tasks.json"
elif [ -d "$CWD/.claude" ] && [ -f "$CWD/.claude/tasks.json" ]; then
    TASKS_FILE="$CWD/.claude/tasks.json"
fi

if [ -n "$TASKS_FILE" ] && [ -f "$TASKS_FILE" ]; then
    # Use brana-query (Rust, 34x faster) if available, fall back to jq
    # Resolution: PLUGIN_DATA > PLUGIN_ROOT > repo
    BRANA_QUERY=""
    [ -x "${CLAUDE_PLUGIN_DATA:-}/brana-query" ] && BRANA_QUERY="${CLAUDE_PLUGIN_DATA}/brana-query"
    [ -z "$BRANA_QUERY" ] && BRANA_QUERY="${CLAUDE_PLUGIN_ROOT:-$GIT_ROOT/system}/cli/rust/target/release/brana-query"
    if [ -x "$BRANA_QUERY" ]; then
        PROJ=$(jq -r '.project // "unknown"' "$TASKS_FILE" 2>/dev/null)
        TOTAL=$("$BRANA_QUERY" --file "$TASKS_FILE" --count 2>/dev/null) || TOTAL=0
        DONE=$("$BRANA_QUERY" --file "$TASKS_FILE" --status done --count 2>/dev/null) || DONE=0
        BUGS=$("$BRANA_QUERY" --file "$TASKS_FILE" --stream bugs --status pending --count 2>/dev/null) || BUGS=0
        NEXT_ID=$("$BRANA_QUERY" --file "$TASKS_FILE" --status pending --output ids 2>/dev/null | head -1) || NEXT_ID=""
        NEXT_SUBJ=""
        NEXT_CTX=""
        if [ -n "$NEXT_ID" ]; then
            NEXT_SUBJ=$(jq -r --arg id "$NEXT_ID" '.tasks[] | select(.id == $id) | .subject' "$TASKS_FILE" 2>/dev/null)
            NEXT_CTX=$(jq -r --arg id "$NEXT_ID" '.tasks[] | select(.id == $id) | .context // empty' "$TASKS_FILE" 2>/dev/null)
        fi
        TASK_SUMMARY="Project: $PROJ ($DONE/$TOTAL)"
        [ "$BUGS" -gt 0 ] 2>/dev/null && TASK_SUMMARY="$TASK_SUMMARY | Bugs: $BUGS open"
        if [ -n "$NEXT_ID" ]; then
            TASK_SUMMARY="$TASK_SUMMARY
Next unblocked: $NEXT_ID $NEXT_SUBJ (pending)"
            [ -n "$NEXT_CTX" ] && TASK_SUMMARY="$TASK_SUMMARY
Context: $NEXT_CTX"
        elif [ "$TOTAL" -gt 0 ] && [ "$TOTAL" = "$DONE" ]; then
            TASK_SUMMARY="$TASK_SUMMARY
All tasks completed. Use /brana:backlog plan for next phase."
        fi
        TASK_SUMMARY="$TASK_SUMMARY
Commands: /brana:backlog next, /brana:backlog plan, /brana:backlog add, /brana:backlog start <id>"
    else
        # Fallback: jq (slower but always available)
        TASK_SUMMARY=$(jq -r '
          .project as $proj |
          ([.tasks[] | select(.status == "completed") | .id]) as $completed |
          ([.tasks[] | select(.type == "task" or .type == "subtask")] | length) as $total |
          ([.tasks[] | select((.type == "task" or .type == "subtask") and .status == "completed")] | length) as $done |
          ([.tasks[] | select(.stream == "bugs" and .status != "completed" and .status != "cancelled")] | length) as $bugs |
          ([.tasks[] | select(
            (.type == "task" or .type == "subtask") and
            .status == "pending" and
            ((.blocked_by // []) | all(. as $b | $completed | index($b) != null))
          )] | sort_by(.order) | first) as $next |
          "Project: \($proj) (\($done)/\($total))" +
          (if $bugs > 0 then " | Bugs: \($bugs) open" else "" end) +
          "\n" +
          (if $next then "Next unblocked: \($next.id) \($next.subject) (pending)"
           elif ($total > 0 and $total == $done) then "All tasks completed. Use /brana:backlog plan for next phase."
           else "" end) +
          "\nCommands: /brana:backlog next, /brana:backlog plan, /brana:backlog add, /brana:backlog start <id>"
        ' "$TASKS_FILE" 2>/dev/null) || true
    fi

    if [ -n "$TASK_SUMMARY" ]; then
        TASK_CONTEXT="[Active tasks] $TASK_SUMMARY"
    fi
else
    TASK_CONTEXT="[Tasks] No tasks.json found. Use /brana:backlog plan to create one."
    PORTFOLIO_FILE="$HOME/.claude/tasks-portfolio.json"
    if [ -f "$PORTFOLIO_FILE" ]; then
        PORTFOLIO_SUMMARY=$(jq -r '
          if .clients then
            [.clients[] | .slug] | join(", ")
          elif .projects then
            [.projects[] | .slug] | join(", ")
          else empty end
        ' "$PORTFOLIO_FILE" 2>/dev/null) || true
        if [ -n "$PORTFOLIO_SUMMARY" ]; then
            TASK_CONTEXT="[Task portfolio] Clients: $PORTFOLIO_SUMMARY. No tasks.json — use /brana:backlog plan to create one."
        fi
    fi
fi

# ── Session handoff (previous session continuity) ─────────
# Suppress with: BRANA_RECAP_OFF=1
HANDOFF_CONTEXT=""
BRANA_BIN=""
[ -x "${CLAUDE_PLUGIN_DATA:-}/brana" ] && BRANA_BIN="${CLAUDE_PLUGIN_DATA}/brana"
[ -z "$BRANA_BIN" ] && [ -x "${CLAUDE_PLUGIN_ROOT:-$GIT_ROOT/system}/cli/rust/target/release/brana" ] && BRANA_BIN="${CLAUDE_PLUGIN_ROOT:-$GIT_ROOT/system}/cli/rust/target/release/brana"
[ -z "$BRANA_BIN" ] && BRANA_BIN=$(command -v brana 2>/dev/null) || true

if [ -z "${BRANA_RECAP_OFF:-}" ] && [ -n "$BRANA_BIN" ]; then
    # Try structured JSON first (new session-state.json)
    # brana session read resolves project from CWD; hook starts in /tmp so
    # we must run it from GIT_ROOT or it reads the wrong (-tmp) project.
    SESSION_JSON=$(cd "$GIT_ROOT" 2>/dev/null && "$BRANA_BIN" session read --json 2>/dev/null) || SESSION_JSON=""
    # Discard auto-captured stub (session-end hook fallback, no useful next[])
    if echo "$SESSION_JSON" | grep -q '"auto-captured'; then SESSION_JSON=""; fi
    if [ -n "$SESSION_JSON" ]; then
        HO_LABEL=$(echo "$SESSION_JSON" | jq -r '.session_label // empty' 2>/dev/null) || true
        HO_DATE=$(echo "$SESSION_JSON" | jq -r '.written_at // empty' 2>/dev/null | cut -dT -f1) || true
        HO_BRANCH=$(echo "$SESSION_JSON" | jq -r '.branch // empty' 2>/dev/null) || true
        HO_NEXT=$(echo "$SESSION_JSON" | jq -r '.next[]? | "[\(.category)] \(.text)" + (if .task_id then " (\(.task_id))" else "" end)' 2>/dev/null | head -10) || true
        HO_BLOCKERS=$(echo "$SESSION_JSON" | jq -r '.blockers[]? | .text + (if .task_id then " (\(.task_id))" else "" end)' 2>/dev/null | head -3) || true

        HANDOFF_CONTEXT="Last session: ${HO_DATE:+$HO_DATE — }${HO_LABEL:-unlabeled}${HO_BRANCH:+ [$HO_BRANCH]}"
        if [ -n "$HO_NEXT" ]; then
            HANDOFF_CONTEXT="$HANDOFF_CONTEXT
Next: $HO_NEXT"
        fi
        if [ -n "$HO_BLOCKERS" ]; then
            HANDOFF_CONTEXT="$HANDOFF_CONTEXT
Blockers: $HO_BLOCKERS"
        fi

        # Mark consumed (optimistic write-first) — must also run from GIT_ROOT
        (cd "$GIT_ROOT" 2>/dev/null && "$BRANA_BIN" session mark-consumed 2>/dev/null) || true
    else
        # Fallback: try legacy markdown handoff
        HANDOFF_RAW=$(cd "$GIT_ROOT" 2>/dev/null && "$BRANA_BIN" handoff last 2>/dev/null) || true
        if [ -n "$HANDOFF_RAW" ]; then
            HO_HEADING=$(echo "$HANDOFF_RAW" | head -1 | sed 's/^## //')
            HO_NEXT=$(echo "$HANDOFF_RAW" | sed -n '/^\*\*Next[^*]*\*\*/,/^\*\*[A-Za-z]/p' | grep -v '^\*\*' | sed 's/^- //' | head -10) || true
            HO_BLOCKERS=$(echo "$HANDOFF_RAW" | sed -n '/^\*\*Blockers:\*\*/,/^\*\*[A-Z]/p' | grep -v '^\*\*' | head -3) || true
            HANDOFF_CONTEXT="Last session: $HO_HEADING"
            if [ -n "$HO_NEXT" ]; then
                HANDOFF_CONTEXT="$HANDOFF_CONTEXT
Next: $HO_NEXT"
            fi
            if [ -n "$HO_BLOCKERS" ] && ! echo "$HO_BLOCKERS" | grep -qi "^none$"; then
                HANDOFF_CONTEXT="$HANDOFF_CONTEXT
Blockers: $HO_BLOCKERS"
            fi
        fi
    fi
fi

# ── Self-learning loop: check flags from previous session ──
LOOP_CONTEXT=""

# Read backprop + doc_drift from structured session state (replaces .needs-backprop flag)
if [ -n "$BRANA_BIN" ] && [ -n "$SESSION_JSON" ]; then
    BP_NEEDED=$(echo "$SESSION_JSON" | jq -r '.backprop.needed // false' 2>/dev/null) || BP_NEEDED="false"
    if [ "$BP_NEEDED" = "true" ]; then
        BP_FILES=$(echo "$SESSION_JSON" | jq -r '.backprop.files[]?' 2>/dev/null | paste -sd ',' || true)
        LOOP_CONTEXT="[Previous session] System files changed ($BP_FILES). Consider running /brana:reconcile to sync specs."
    fi
    DD_DETECTED=$(echo "$SESSION_JSON" | jq -r '.doc_drift.detected // false' 2>/dev/null) || DD_DETECTED="false"
    if [ "$DD_DETECTED" = "true" ]; then
        DD_DOCS=$(echo "$SESSION_JSON" | jq -r '.doc_drift.stale_docs[]?' 2>/dev/null | paste -sd ', ' || true)
        LOOP_CONTEXT="${LOOP_CONTEXT:+$LOOP_CONTEXT
}[Stale docs] These docs may need updating: $DD_DOCS. Review or run /brana:reconcile."
    fi
fi

# Fallback: check .needs-backprop flag file (legacy, during migration)
if [ -z "$SESSION_JSON" ]; then
    LAYER0_DIR=""
    for projdir in "$HOME"/.claude/projects/*/; do
        if [ -d "${projdir}memory" ]; then
            if grep -qi "$PROJECT" "${projdir}memory/MEMORY.md" 2>/dev/null; then
                LAYER0_DIR="${projdir}memory"
                break
            fi
        fi
    done

    if [ -n "$LAYER0_DIR" ]; then
        BACKPROP_FLAG="$LAYER0_DIR/.needs-backprop"
        if [ -f "$BACKPROP_FLAG" ]; then
            DRIFT_INFO=$(cat "$BACKPROP_FLAG" 2>/dev/null) || true
            DOCS_STALE=$(echo "$DRIFT_INFO" | grep "^docs-stale:" | sed 's/^docs-stale: //' || true)
            SYS_DRIFT=$(echo "$DRIFT_INFO" | grep -v "^docs-stale:" || true)
            if [ -n "$SYS_DRIFT" ]; then
                LOOP_CONTEXT="[Previous session] System files changed ($SYS_DRIFT). Consider running /brana:reconcile to sync specs."
            fi
            if [ -n "$DOCS_STALE" ]; then
                LOOP_CONTEXT="$LOOP_CONTEXT
[Stale feature docs] These docs may need updating: $DOCS_STALE. Review or run /brana:reconcile."
            fi
            rm -f "$BACKPROP_FLAG"
        fi
    fi
fi

# Check pending learnings (still uses auto memory dir)
LAYER0_DIR=""
for projdir in "$HOME"/.claude/projects/*/; do
    if [ -d "${projdir}memory" ]; then
        if grep -qi "$PROJECT" "${projdir}memory/MEMORY.md" 2>/dev/null; then
            LAYER0_DIR="${projdir}memory"
            break
        fi
    fi
done
if [ -n "$LAYER0_DIR" ] && [ -f "$LAYER0_DIR/pending-learnings.md" ]; then
    PENDING_COUNT=$(grep -c '^## Session' "$LAYER0_DIR/pending-learnings.md" 2>/dev/null) || PENDING_COUNT=0
    if [ "$PENDING_COUNT" -gt 0 ]; then
        LOOP_CONTEXT="${LOOP_CONTEXT:+$LOOP_CONTEXT
}[Pending learnings] $PENDING_COUNT unprocessed session(s) in pending-learnings.md. Consider running /brana:close to extract learnings."
    fi
fi

# ── Session argument hints (top-6 skills by usage, t-1434 / t-1437) ──
SKILL_HINTS_CONTEXT=""
if [ -n "$BRANA_BIN" ]; then
    SKILLS_LIST_JSON=$(cd "$GIT_ROOT" && "$BRANA_BIN" skills list 2>/dev/null) || SKILLS_LIST_JSON=""
    TOP_USAGE=$(cd "$GIT_ROOT" && "$BRANA_BIN" skills usage --days 30 --json 2>/dev/null \
        | jq -r '[.skills[].name] | .[:6] | .[]' 2>/dev/null) || TOP_USAGE=""
    if [ -n "$TOP_USAGE" ] && [ -n "$SKILLS_LIST_JSON" ]; then
        HINT_LINES=""
        while IFS= read -r skill_name; do
            slug="${skill_name#brana:}"
            slug="${slug#plugin:brana:}"
            hint=$(echo "$SKILLS_LIST_JSON" | jq -r --arg n "$slug" \
                '.[] | select(.name == $n) | .argument_hint // ""' 2>/dev/null | head -1) || hint=""
            HINT_LINES="${HINT_LINES:+$HINT_LINES
}/$skill_name${hint:+ $hint}"
        done <<< "$TOP_USAGE"
        [ -n "$HINT_LINES" ] && SKILL_HINTS_CONTEXT="Top skills (by usage):
$HINT_LINES"
    fi
fi

# ── Recurring error detection (t-679) ────────────────────
RECURRENCE_CONTEXT=""
RECURRENCE_FILE="$HOME/.claude/logs/error-recurrence.jsonl"
if [ -f "$RECURRENCE_FILE" ]; then
    # Extract unique hashes with count >= 3 (last entry per hash is authoritative)
    # Use tac + awk to get latest entry per hash, then filter by count
    RECURRING=$(tac "$RECURRENCE_FILE" 2>/dev/null \
        | jq -r -c 'select(.count >= 3)' 2>/dev/null \
        | awk -F'"hash":"' '!seen[substr($2,1,16)]++' 2>/dev/null \
        | head -5 \
        | jq -r '"- \(.tool) \(.error_cat): \(.detail) (x\(.count))"' 2>/dev/null) || RECURRING=""
    if [ -n "$RECURRING" ]; then
        RECURRENCE_CONTEXT="[Recurring errors -- rule/hook candidates]
$RECURRING"
    fi
fi

# ── Venture project detection (shared lib) ────────────────
# Suppress with: BRANA_RECAP_OFF=1
VENTURE_CONTEXT=""
source "$SCRIPT_DIR/lib/venture.sh"
IS_VENTURE=false
_detect_venture "$CWD" && IS_VENTURE=true

if [ -z "${BRANA_RECAP_OFF:-}" ] && [ "$IS_VENTURE" = true ]; then
    VENTURE_CONTEXT="Venture project detected. Auto-delegating to daily-ops agent for morning check."

    NEWEST_REVIEW=""
    if [ -d "$CWD/docs/reviews" ]; then
        NEWEST_REVIEW=$(find "$CWD/docs/reviews" -name 'weekly-*.md' -type f -printf '%T@\n' 2>/dev/null | sort -rn | head -1 || true)
    fi

    if [ -n "$NEWEST_REVIEW" ]; then
        NOW=$(date +%s 2>/dev/null) || NOW=0
        AGE_SECONDS=$(echo "$NOW - ${NEWEST_REVIEW%.*}" | bc 2>/dev/null) || AGE_SECONDS=0
        SEVEN_DAYS=604800
        if [ "$AGE_SECONDS" -gt "$SEVEN_DAYS" ]; then
            DAYS_AGO=$(( AGE_SECONDS / 86400 ))
            VENTURE_CONTEXT="$VENTURE_CONTEXT
Weekly review is ${DAYS_AGO} days old. Consider running /brana:review weekly."
        fi
    else
        VENTURE_CONTEXT="$VENTURE_CONTEXT
No weekly review found. Consider running /brana:review weekly."
    fi
fi

# ══════════════════════════════════════════════════════════
# PHASE 3: Collect parallel results (max 5s combined wait)
# ══════════════════════════════════════════════════════════
_mark "phase3-wait-start"

# Wait for all parallel jobs with a hard deadline.
# If any job is still running after the budget, kill it and proceed with
# partial results. Budget 2s→5s (t-1937): a single ruflo CLI node startup
# costs ~1.5-2s; with the recall job (ONNX load ~1.6s) and flywheel insight
# running in parallel, 2s killed whichever job didn't overlap phase 2.
if [ -n "$PIDS" ]; then
    WAIT_START=$(( $(date +%s) * 1000 ))
    for pid in $PIDS; do
        # Calculate remaining budget
        NOW_MS=$(( $(date +%s) * 1000 ))
        ELAPSED_MS=$((NOW_MS - WAIT_START))
        REMAINING_MS=$((5000 - ELAPSED_MS))
        if [ "$REMAINING_MS" -le 0 ]; then
            # Budget exhausted — kill remaining jobs
            kill $pid 2>/dev/null || true
            continue
        fi
        # Wait with per-job timeout (bash wait doesn't support timeout, use kill after delay)
        ( sleep $(( (REMAINING_MS + 999) / 1000 )) && kill $pid 2>/dev/null ) &
        KILLER=$!
        wait $pid 2>/dev/null || true
        kill $KILLER 2>/dev/null || true
        wait $KILLER 2>/dev/null || true
    done
fi

# Wait for hybrid recall (Job 1c) — separate from PIDS to avoid the kill-loop
# timing issue (date +%s%3N gives nanoseconds on Linux, not milliseconds).
# 3-second wall-clock cap matches the timeout inside the subshell.
if [ -n "${RECALL_PID:-}" ]; then
    ( sleep 3 && kill "$RECALL_PID" 2>/dev/null ) &
    _RECALL_KILLER=$!
    wait "$RECALL_PID" 2>/dev/null || true
    kill "$_RECALL_KILLER" 2>/dev/null || true
    wait "$_RECALL_KILLER" 2>/dev/null || true
fi

# Read results from temp files
CONTEXT=""
if [ -f "$TMPDIR_SS/cf-context" ]; then
    CONTEXT=$(cat "$TMPDIR_SS/cf-context" 2>/dev/null) || true
fi

if [ -f "$TMPDIR_SS/cf-warning" ]; then
    CF_WARN_TYPE=$(cat "$TMPDIR_SS/cf-warning" 2>/dev/null) || true
    if [ "$CF_WARN_TYPE" = "TIMEOUT" ]; then
        CF_WARNING="Memory search timed out (>8s). Patterns not recalled. Try: ~/.claude/scripts/ruflo-cli.sh memory search --query \"$PROJECT patterns\" --namespace pattern --threshold 0.3"
    elif [ "$CF_WARN_TYPE" = "FAILED" ]; then
        CF_WARNING="Memory search FAILED (ruflo invocation error — check ~/.claude/scripts/ruflo-cli.sh). Patterns not recalled this session."
    fi
fi

CORRECTION_CONTEXT=""
if [ -f "$TMPDIR_SS/corrections" ]; then
    CP_LINES=$(cat "$TMPDIR_SS/corrections" 2>/dev/null) || true
    if [ -n "$CP_LINES" ]; then
        CORRECTION_CONTEXT="[Correction patterns — high confidence, apply early if similar errors arise]
$CP_LINES"
    fi
fi

# Flywheel observation (t-1937) — one metrics-derived line per session
FLYWHEEL_CONTEXT=""
if [ -f "$TMPDIR_SS/flywheel-insight" ]; then
    FW_LINE=$(head -1 "$TMPDIR_SS/flywheel-insight" 2>/dev/null) || true
    if [ -n "$FW_LINE" ]; then
        FLYWHEEL_CONTEXT="[Flywheel] $FW_LINE"
    fi
fi

# Hybrid recall (Job 1c) — FTS5 + ruflo combined results (t-2096)
HYBRID_RECALL_CONTEXT=""
if [ -f "$TMPDIR_SS/hybrid-recall" ]; then
    HYBRID_RECALL_CONTEXT=$(cat "$TMPDIR_SS/hybrid-recall" 2>/dev/null) || true
fi

# Fallback: grep native auto memory if CF returned nothing
if [ -z "$CONTEXT" ]; then
    MEMORY_HIT=""
    for memfile in "$HOME"/.claude/projects/*/memory/MEMORY.md; do
        if [ -f "$memfile" ]; then
            MATCH=$(grep -i "$PROJECT" "$memfile" 2>/dev/null | head -5 || true)
            if [ -n "$MATCH" ]; then
                MEMORY_HIT="$MEMORY_HIT$MATCH"$'\n'
            fi
        fi
    done
    if [ -n "$MEMORY_HIT" ]; then
        CONTEXT="$MEMORY_HIT"
    fi
fi

_mark "phase3-wait-done"
# ══════════════════════════════════════════════════════════
# PHASE 4: Assemble and emit JSON response
# ══════════════════════════════════════════════════════════

OUTPUT_PARTS=""
if [ -n "$CONTEXT" ]; then
    OUTPUT_PARTS="[Recalled patterns — confidence:quarantine means unproven, treat with caution. confidence:proven means validated across 3+ sessions.]
$CONTEXT"
fi
if [ -n "$HYBRID_RECALL_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}[Hybrid recall]
$HYBRID_RECALL_CONTEXT"
fi
if [ -n "$TASK_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}$TASK_CONTEXT"
fi
if [ -n "$SKILL_HINTS_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}[Skill hints] $SKILL_HINTS_CONTEXT"
fi
if [ -n "$HANDOFF_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}[Session handoff] $HANDOFF_CONTEXT"
fi
if [ -n "$CORRECTION_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}$CORRECTION_CONTEXT"
fi
if [ -n "$FLYWHEEL_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}$FLYWHEEL_CONTEXT"
fi
if [ -n "$PERSIST_FAIL_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}$PERSIST_FAIL_CONTEXT"
fi
if [ -n "$SCHED_FAIL_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}$SCHED_FAIL_CONTEXT"
fi
if [ -n "$CQ_STALE_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}$CQ_STALE_CONTEXT"
fi
if [ -n "$LOOP_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}$LOOP_CONTEXT"
fi
if [ -n "$VENTURE_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}[Venture] $VENTURE_CONTEXT"
fi
if [ -n "$RECURRENCE_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}$RECURRENCE_CONTEXT"
fi
if [ -n "$CF_WARNING" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}[Hook warning] $CF_WARNING"
fi
if [ -n "$TMP_WARNING" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}[Disk] $TMP_WARNING"
fi
# CC changelog report (weekly check)
CC_REPORT="$HOME/.claude/cc-changelog-report.md"
if [ -f "$CC_REPORT" ]; then
    CC_SUMMARY=$(head -5 "$CC_REPORT" | tail -3 2>/dev/null) || CC_SUMMARY=""
    if [ -n "$CC_SUMMARY" ]; then
        OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}[CC changelog] New changes detected. Review: ~/.claude/cc-changelog-report.md"
    fi
fi
# Intelligence feed digest (daily feed-index job)
FEED_DIGEST="$HOME/.claude/intelligence-feed-digest.md"
if [ -f "$FEED_DIGEST" ]; then
    FEED_COUNT=$(grep -c '^[0-9]\{4\}' "$FEED_DIGEST" 2>/dev/null) || FEED_COUNT="?"
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}[Intelligence feed] $FEED_COUNT new items. Review: ~/.claude/intelligence-feed-digest.md"
fi
if [ -n "$DRIFT_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}[Config drift] $DRIFT_CONTEXT"
fi
if [ -n "$SENTINEL_WARNING" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}[Bootstrap] $SENTINEL_WARNING"
fi
if [ -n "$STALE_BINARY_WARNING" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}[Stale binary] $STALE_BINARY_WARNING"
fi
if [ -n "$REMINDER_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}[Reminders] Reminders: $REMINDER_CONTEXT"
fi
if [ -n "$YESTERDAY_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}[Yesterday] $YESTERDAY_CONTEXT"
fi
if [ -n "$LINT_HEAL_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}[Lint+Heal] $LINT_HEAL_CONTEXT"
fi
if [ -n "$EU_WARNING" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}[Extra-usage] $EU_WARNING"
fi

# ── Write context readback file (survives context compression) ──
CONTEXT_FILE="/tmp/brana-context-${SESSION_ID}.md"
{
    echo "# Session Context"
    echo ""
    echo "**Session:** $SESSION_ID"
    echo "**Project:** $PROJECT"
    echo "**Date:** $(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%d)"
    echo ""
    if [ -n "$OUTPUT_PARTS" ]; then
        echo "$OUTPUT_PARTS"
    fi
} > "$CONTEXT_FILE" 2>/dev/null || true

if [ -n "$OUTPUT_PARTS" ]; then
    ESCAPED=$(echo "$OUTPUT_PARTS" | jq -Rs '.' 2>/dev/null) || ESCAPED='""'
    echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
else
    echo '{"continue": true}'
fi

_mark "hook-end"
# ══════════════════════════════════════════════════════════
# PHASE 5: Fork non-essential work to background
# ══════════════════════════════════════════════════════════

(
    SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"

    # Log recalled patterns to session file for promotion tracking (t-203)
    if [ -n "$CONTEXT" ]; then
        RECALLED_KEYS_SS=$(cat "$TMPDIR_SS/recalled-keys" 2>/dev/null) || RECALLED_KEYS_SS="[]"
        jq -n -c \
            --argjson ts "$(date +%s 2>/dev/null || echo 0)" \
            --arg tool "session-start" \
            --arg outcome "recall" \
            --arg detail "$CONTEXT" \
            --argjson keys "${RECALLED_KEYS_SS:-[]}" \
            '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail, keys: $keys}' >> "$SESSION_FILE" 2>/dev/null || true
    fi

    # Log venture detection to session file
    if [ "$IS_VENTURE" = true ] && [ -n "$VENTURE_CONTEXT" ]; then
        jq -n -c \
            --argjson ts "$(date +%s 2>/dev/null || echo 0)" \
            --arg tool "session-start-venture" \
            --arg outcome "venture-detected" \
            --arg detail "$VENTURE_CONTEXT" \
            '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE" 2>/dev/null || true
    fi

    # Index skills into ruflo memory (only changed since last run)
    INDEX_SKILLS="$SCRIPT_DIR/../scripts/index-skills.sh"
    if [ -x "$INDEX_SKILLS" ]; then
        "$INDEX_SKILLS" --changed 2>/dev/null || true
    fi

    # ADR-038: regenerate MEMORY.md from filesystem at session start.
    # Full regeneration catches files written by previous sessions and ensures
    # "newest dated file wins" logic is applied across all accumulated writes.
    if [ -n "$BRANA_BIN" ]; then
        (cd "$GIT_ROOT" && "$BRANA_BIN" memory index --scope project 2>/dev/null) || true
    fi

    # ADR-015: sync operational state from cache to repos (push)
    SYNC_SCRIPT="$SCRIPT_DIR/../scripts/sync-state.sh"
    if [ -x "$SYNC_SCRIPT" ]; then
        "$SYNC_SCRIPT" push 2>/dev/null || true
    fi
) &
disown 2>/dev/null || true
