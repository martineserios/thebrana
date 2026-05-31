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
Cw='\033[97m' Cy='\033[36m' Co='\033[33m' Cr='\033[31m'
S="${D}│${R}"

# ── Project name ─────────────────────────────────────────
GIT_ROOT=$(cd "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
PROJ_NAME=$(basename "${GIT_ROOT:-$CWD}")

# ── Branch ───────────────────────────────────────────────
BRANCH=$(cd "$CWD" 2>/dev/null && git branch --show-current 2>/dev/null)

# ── CTX color ────────────────────────────────────────────
COMPACT_THRESHOLD=${BRANA_AUTOCOMPACT_THRESHOLD:-85}
UNTIL_COMPACT=$(( COMPACT_THRESHOLD - CTX_PCT ))

if   (( UNTIL_COMPACT <= 0  )); then CTX_SHOW="${Cr}${B}🔴 CTX ${CTX_PCT}%${R}"
elif (( UNTIL_COMPACT <= 15 )); then CTX_SHOW="${Cr}⚠ CTX ${CTX_PCT}% ${D}·${UNTIL_COMPACT}c${R}"
elif (( UNTIL_COMPACT <= 30 )); then CTX_SHOW="${Co}⚠ CTX ${CTX_PCT}%${R}"
elif (( UNTIL_COMPACT <= 45 )); then CTX_SHOW="${Co}CTX ${CTX_PCT}%${R}"
else                                  CTX_SHOW="${D}CTX ${CTX_PCT}%${R}"; fi

# ── Output ───────────────────────────────────────────────
printf '%b' "🧠 ${B}${Cw}${MODEL}${R} ${S} 📂 ${Cy}${PROJ_NAME}${R}"
[ -n "$BRANCH" ] && printf '%b' " ${S} 🌿 ${Co}${BRANCH}${R}"
printf '%b' " ${S} ${CTX_SHOW}"
echo
