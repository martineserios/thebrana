#!/bin/bash
# ─── Claude Code Statusline ─────────────────────────────
# 🧠 Model │ 📂 project │ 🌿 branch │ CTX NN%

INPUT=$(cat)

IFS=$'\t' read -r MODEL CWD CTX_PCT <<< \
  "$(echo "$INPUT" | jq -r '[
    (.model.display_name // "Claude"),
    (.workspace.current_dir // .cwd // "."),
    (.context_window.used_percentage // 0 | floor)
  ] | @tsv')"

CTX_PCT=${CTX_PCT:-0}

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
# sit on main/dev, so fall back to the project's own active_epic there.
# Project-local only (ADR-066): active_epic has exactly one authoritative
# source, the resolving project's config — the global ~/.claude copy is never
# valid for this key. thebrana keeps its copy at system/state/, others at
# .claude/; both are project-local, so check each in turn.
EPIC=""
if [[ "$BRANCH" == */*/t-* ]]; then
    EPIC="${BRANCH%%/*}"
elif [ -n "$GIT_ROOT" ]; then
    for cfg in "$GIT_ROOT/.claude/tasks-config.json" \
               "$GIT_ROOT/system/state/tasks-config.json"; do
        [ -f "$cfg" ] || continue
        EPIC=$(jq -r '.active_epic // empty' "$cfg" 2>/dev/null)
        [ -n "$EPIC" ] && break
    done
    # The output below goes through printf '%b', which interprets backslash
    # escapes; a literal or escaped newline would break the one-line contract.
    # Branch names can't contain these (git forbids them in refs) — only a
    # hand-edited config can, so scrub after the config path.
    EPIC=${EPIC//\\/}
    EPIC=${EPIC//$'\n'/}
    EPIC=${EPIC//$'\r'/}
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
printf '%b' " ${S} ${CTX_SHOW}"
echo
