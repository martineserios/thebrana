#!/bin/bash
# ─── Claude Code Statusline ─────────────────────────────
# 🧠 Model │ 📂 project │ 🌿 branch │ CTX NN% │ 📝 +156 -23 │ [⚡ │ 📋 N]
# CTX color: green <55%, yellow 55-69%, orange 70-84%, red 85%+

INPUT=$(cat)

# ── Parse all fields in one jq call ──────────────────────
IFS=$'\t' read -r MODEL CWD PROJECT CTX_PCT LA LD <<< \
  "$(echo "$INPUT" | jq -r '[
    (.model.display_name // "Claude"),
    (.workspace.current_dir // .cwd // "."),
    (.workspace.project_dir // .cwd // "."),
    (.context_window.used_percentage // 0 | floor),
    (.cost.total_lines_added // 0),
    (.cost.total_lines_removed // 0)
  ] | @tsv')"

CTX_PCT=${CTX_PCT:-0}; LA=${LA:-0}; LD=${LD:-0}

# ── ANSI palette ─────────────────────────────────────────
R='\033[0m'   D='\033[2m'   B='\033[1m'
Cw='\033[97m' Cy='\033[36m' Cg='\033[32m'
Cr='\033[31m' Cm='\033[35m' Co='\033[33m'
S="${D}│${R}"

# ── Project name: git repo root > directory basename ─────
PROJ_NAME=""
GIT_ROOT=$(cd "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$GIT_ROOT" ]; then
  PROJ_NAME=$(basename "$GIT_ROOT")
else
  PROJ_NAME=$(basename "$PROJECT")
fi

# ── Context indicator (always visible, color-coded) ──────
if   (( CTX_PCT >= 95 )); then CTX_SHOW="${Cr}${B}🔴 CTX ${CTX_PCT}%${R}"
elif (( CTX_PCT >= 85 )); then CTX_SHOW="${Cr}⚠ CTX ${CTX_PCT}%${R}"
elif (( CTX_PCT >= 70 )); then CTX_SHOW="${Co}⚠ CTX ${CTX_PCT}%${R}"
elif (( CTX_PCT >= 55 )); then CTX_SHOW="${Co}CTX ${CTX_PCT}%${R}"
else                            CTX_SHOW="${D}CTX ${CTX_PCT}%${R}"; fi

# ── Git branch ───────────────────────────────────────────
BRANCH=$(cd "$CWD" 2>/dev/null && git branch --show-current 2>/dev/null)

# ── Output ──────────────────────────────────────────────
printf '%b' "🧠 ${B}${Cw}${MODEL}${R}"
printf '%b' " $S 📂 ${Cy}${PROJ_NAME}${R}"
[ -n "$BRANCH" ] && printf '%b' " $S 🌿 ${Co}${BRANCH}${R}"
printf '%b' " $S ${CTX_SHOW}"
printf '%b' " $S 📝 ${Cg}+${LA}${R} ${Cr}-${LD}${R}"
# Claude-flow metrics (only when active)
FD="$CWD/.claude-flow"
if [ -d "$FD" ] && [ -f "$FD/swarm-config.json" ]; then
  IFS=$'\t' read -r STR AC <<< \
    "$(jq -r '[(.defaultStrategy // ""), (.agentProfiles | length // 0)] | @tsv' \
      "$FD/swarm-config.json" 2>/dev/null)"
  [ -n "$STR" ] && printf '%b' " $S ⚡ ${Cm}${STR}${R}"
  (( AC > 0 )) 2>/dev/null && printf '%b' " 🤖 ${Cm}${AC}${R}"
fi
if [ -d "$FD/tasks" ]; then
  TC=$(find "$FD/tasks" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
  (( TC > 0 )) && printf '%b' " $S 📋 ${Cy}${TC}${R}"
fi
# ── Task metrics ───────────────────────────────────────
TASK_FILE=""
for TF in "$CWD/.claude/tasks.json" "$PROJECT/.claude/tasks.json"; do
  [ -f "$TF" ] && TASK_FILE="$TF" && break
done
if [ -n "$TASK_FILE" ]; then
  # Read from cache (written by post-tasks-validate.sh on every tasks.json write)
  CACHE_FILE="${TASK_FILE%.json}.statusline.tsv"
  if [ -f "$CACHE_FILE" ]; then
    IFS=$'\t' read -r T_PHASE T_DONE T_TOTAL T_CURRENT T_BUGS T_BUILD_STEP < "$CACHE_FILE"
  else
    # Fallback: compute directly (first run before any task write)
    IFS=$'\t' read -r T_PHASE T_DONE T_TOTAL T_CURRENT T_BUGS T_BUILD_STEP <<< \
      "$(jq -r '[
        ([.tasks[] | select(.type == "phase" and .status == "in_progress")] | first | .subject // "" | split(":") | first | ltrimstr("Phase ") // ""),
        ([.tasks[] | select((.type == "task" or .type == "subtask") and .status == "completed")] | length),
        ([.tasks[] | select(.type == "task" or .type == "subtask")] | length),
        ([.tasks[] | select(.status == "in_progress" and (.type == "task" or .type == "subtask"))] | first | .subject // ""),
        ([.tasks[] | select(.stream == "bugs" and .status != "completed" and .status != "cancelled")] | length),
        ([.tasks[] | select(.status == "in_progress" and (.type == "task" or .type == "subtask"))] | first | .build_step // "")
      ] | @tsv' "$TASK_FILE" 2>/dev/null)"
  fi
  # Phase progress
  if [ -n "$T_PHASE" ] && (( T_TOTAL > 0 )); then
    printf '%b' " $S 📋 ${Cy}Ph${T_PHASE}: ${T_DONE}/${T_TOTAL}${R}"
  fi
  # Current task (truncate to 25 chars)
  if [ -n "$T_CURRENT" ]; then
    TC="${T_CURRENT:0:25}"
    printf '%b' " $S → ${Cw}${TC}${R}"
  fi
  # Build step bracket
  if [ -n "${T_BUILD_STEP:-}" ]; then
    printf '%b' " ${Cm}[${T_BUILD_STEP}]${R}"
  fi
  # Bug count
  if (( T_BUGS > 0 )) 2>/dev/null; then
    printf '%b' " $S 🐛 ${Cr}${T_BUGS}${R}"
  fi
fi
# ── Scheduler health ─────────────────────────────────
SCHED_STATUS="$HOME/.claude/scheduler/last-status.json"
if [ -f "$SCHED_STATUS" ]; then
  IFS=$'\t' read -r S_OK S_FAIL <<< \
    "$(jq -r '[
      ([.[] | select(.status == "SUCCESS")] | length),
      ([.[] | select(.status == "FAILED" or .status == "TIMEOUT")] | length)
    ] | @tsv' "$SCHED_STATUS" 2>/dev/null)"
  S_OK=${S_OK:-0}; S_FAIL=${S_FAIL:-0}
  if (( S_FAIL > 0 )); then
    printf '%b' " $S 📅 ${Cg}${S_OK}✓${R} ${Cr}${S_FAIL}✗${R}"
  elif (( S_OK > 0 )); then
    printf '%b' " $S 📅 ${Cg}${S_OK}✓${R}"
  fi
fi
echo
