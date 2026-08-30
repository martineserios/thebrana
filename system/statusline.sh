#!/bin/bash
# ─── Claude Code Statusline ─────────────────────────────
# 🧠 Model │ 📂 project │ 🌿 branch │ 🎯 epic │ 🪪 session │ CTX NN%

INPUT=$(cat)

IFS=$'\t' read -r MODEL CWD CTX_PCT SESSION_ID <<< \
  "$(echo "$INPUT" | jq -r '[
    (.model.display_name // "Claude"),
    (.workspace.current_dir // .cwd // "."),
    (.context_window.used_percentage // 0 | floor),
    (.session_id // "")
  ] | @tsv')"

CTX_PCT=${CTX_PCT:-0}
SESSION_SHORT="${SESSION_ID:0:8}"

# Prefer the fleet name CC's own multi-agent addressing (ListAgents/SendMessage)
# uses for this session — a single keyed file read (~/.claude/sessions/$CLAUDE_PID.json),
# never a scan of the whole sessions/ directory (t-3246: 495+ files there already).
# Cross-check .sessionId against the input's session_id before trusting .name: this
# is what makes the lookup no-op safely under a leaked/ambient CLAUDE_PID that
# doesn't belong to the session being rendered (e.g. inside these very tests).
if [ -n "$CLAUDE_PID" ] && [ -n "$SESSION_ID" ]; then
  SESSION_REG_FILE="$HOME/.claude/sessions/${CLAUDE_PID}.json"
  if [ -r "$SESSION_REG_FILE" ]; then
    IFS=$'\t' read -r REG_SID REG_NAME <<< \
      "$(jq -r '[(.sessionId // ""), (.name // "")] | @tsv' "$SESSION_REG_FILE" 2>/dev/null)"
    [ -n "$REG_NAME" ] && [ "$REG_SID" = "$SESSION_ID" ] && SESSION_SHORT="$REG_NAME"
  fi
fi

# Scrub before the printf '%b' render sink, same as EPIC below (t-2731 challenger
# finding): %b interprets backslash escapes, and a stray one or raw control byte
# would break the one-line contract.
SESSION_SHORT=${SESSION_SHORT//\\/}
SESSION_SHORT=$(printf '%s' "$SESSION_SHORT" | tr -d '[:cntrl:]')

# ── ANSI palette ─────────────────────────────────────────
R='\033[0m' D='\033[2m' B='\033[1m'
Cw='\033[97m' Cy='\033[36m' Cg='\033[32m' Co='\033[38;5;208m' Cr='\033[31m' Cf='\033[38;5;220m'
BGg='\033[42m' BGo='\033[48;5;208m' BGr='\033[41m' BGe='\033[100m'
S="${D}│${R}"

# ── Project name ─────────────────────────────────────────
GIT_ROOT=$(cd "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
PROJ_NAME=$(basename "${GIT_ROOT:-$CWD}")

# ── Branch ───────────────────────────────────────────────
BRANCH=$(cd "$CWD" 2>/dev/null && git branch --show-current 2>/dev/null)

# ── Current task epic ────────────────────────────────────
# Task-branch convention: {epic}/{work-type}/t-{NNN}-{slug}. Show the epic
# (first segment) only for real task branches — never dev/main/docs/*.
# Clients/ventures use the 2-segment convention (feat/t-NNN-slug) and mostly
# sit on main/dev, so on those branches prefer the epic of whichever task is
# actually being worked (most-recently-started in_progress task's flat
# `.epic` field — the pre-v3 schema still used by client/venture projects;
# thebrana's own v3 parent-chain epics aren't resolved here, a hot-path
# statusline render isn't the place for a multi-hop lookup, so those degrade
# to no epic shown, same as before, t-2639).
# ADR-088 (t-3196): the static tasks-config.json fallback that used to sit
# here is retired along with the shared config file itself — resolution is
# task-derived only (branch segment, then dynamic in-progress task), matching
# brana-core's resolve_focus_epic(). No config file is read for this anymore.
EPIC=""
if [[ "$BRANCH" == */*/t-* ]]; then
    EPIC="${BRANCH%%/*}"
elif [ -n "$GIT_ROOT" ]; then
    # Cheap pre-check before the jq scan (t-2641): thebrana's own tasks.json
    # has zero tasks carrying the flat .epic field (v3 uses parent-chain
    # epics instead — see the elif's own comment below), so on thebrana's
    # own dev branch the jq parse+sort below was previously an unconditional
    # ~40ms cost on a 2500+-task file for a guaranteed-empty result every
    # single render. A plain-text grep for a non-empty "epic" value is ~10x
    # cheaper and lets thebrana (and any other v3-schema project) skip the
    # jq scan entirely; v2-schema projects like proyecto_anita still match
    # and pay the full scan same as before. Allow optional whitespace after
    # the colon — every known tasks.json writer here (brana-cli, brana-mcp)
    # pretty-prints (`"epic": "x"`, space after colon), not compact
    # (`"epic":"x"`); the distinguishing factor across projects is whether
    # the key appears at all (v3 vs v2 schema), not compact-vs-pretty
    # formatting — an earlier version of this pattern assumed the latter and
    # silently broke on proyecto_anita before being caught pre-commit.
    # Known limitation: this is a line-scoped grep, not a JSON parser — a
    # hypothetical writer that split `"epic"` and its `: "value"` across two
    # lines would evade it and fail safe to the static fallback (verified no
    # current writer does this; not worth a multi-line-tolerant pattern for
    # a case no writer produces).
    if [ -f "$GIT_ROOT/.claude/tasks.json" ] && grep -qE '"epic"[[:space:]]*:[[:space:]]*"[^"]' "$GIT_ROOT/.claude/tasks.json" 2>/dev/null; then
        # `.started` is date-only in practice (no time component), so ties are
        # a realistic outcome under this project's own concurrent-work style,
        # not a rare edge — break them by numeric task id (higher id = created
        # later) instead of leaving jq's stable sort to fall back to whatever
        # order the tasks happen to appear in the file (t-2639 challenger).
        EPIC=$(jq -r '
            [ (.tasks // [])[] | select(.status == "in_progress") | select((.epic // "") != "")
              | . + {_idnum: ((.id // "0") | sub("^[a-zA-Z]+-"; "") | tonumber? // 0)} ]
            | sort_by([.started // "", ._idnum])
            | reverse
            | .[0].epic // empty
        ' "$GIT_ROOT/.claude/tasks.json" 2>/dev/null)
    fi
    # The output below goes through printf '%b', which interprets backslash
    # escapes; a literal or escaped newline would break the one-line contract.
    # Branch names can't contain these (git forbids them in refs), but both
    # config sources here are hand-edited or automation-written JSON, so
    # scrub after either path. Strip all raw control bytes (not just \n/\r)
    # — a JSON control-character escape (ESC, 0x1B) or similar decodes to a literal byte with no
    # backslash character for the first pass to catch, and t-2639 widened
    # this scrub's reach from one hand-set config key to every task's .epic
    # field (any write path: CLI/MCP/agent), so the narrower two-char strip
    # was no longer enough (t-2639 challenger).
    EPIC=${EPIC//\\/}
    EPIC=$(printf '%s' "$EPIC" | tr -d '[:cntrl:]')
fi

# ── CTX bar ──────────────────────────────────────────────
COMPACT_THRESHOLD=${BRANA_AUTOCOMPACT_THRESHOLD:-85}
UNTIL_COMPACT=$(( COMPACT_THRESHOLD - CTX_PCT ))

BAR_WIDTH=8
FILLED=$(( CTX_PCT * BAR_WIDTH / 100 ))
EMPTY=$(( BAR_WIDTH - FILLED ))
BAR_FILL=$(printf "%${FILLED}s")
BAR_EMPTY=$(printf "%${EMPTY}s")

if   (( UNTIL_COMPACT <= 0  )); then
    CTX_SHOW="${D}CTX${R} ${BGr}${BAR_FILL}${BGe}${BAR_EMPTY}${R} ${Cr}${B}${CTX_PCT}%${R} ${Cr}${B}COMPACT${R}"
elif (( CTX_PCT >= 75 )); then
    CTX_SHOW="${D}CTX${R} ${BGo}${BAR_FILL}${BGe}${BAR_EMPTY}${R} ${Co}${CTX_PCT}%${R} ${Co}COMPACT${R}"
elif (( CTX_PCT >= 55 )); then
    CTX_SHOW="${D}CTX${R} ${BGo}${BAR_FILL}${BGe}${BAR_EMPTY}${R} ${Co}${CTX_PCT}%${R}"
else
    CTX_SHOW="${D}CTX${R} ${BGg}${BAR_FILL}${BGe}${BAR_EMPTY}${R} ${D}${CTX_PCT}%${R}"
fi

# ── Output ───────────────────────────────────────────────
printf '%b' "🧠 ${B}${Cw}${MODEL}${R} ${S} 📂 ${Cy}${PROJ_NAME}${R}"
[ -n "$BRANCH" ] && printf '%b' " ${S} @ ${Cf}${BRANCH}${R}"
[ -n "$EPIC" ] && printf '%b' " ${S} 🎯 ${Cg}${EPIC}${R}"
[ -n "$SESSION_SHORT" ] && printf '%b' " ${S} 🪪 ${D}${SESSION_SHORT}${R}"
printf '%b' " ${S} ${CTX_SHOW}"
echo
