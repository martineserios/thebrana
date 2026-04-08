#!/bin/bash
# ─── Claude Code Statusline ─────────────────────────────
# 🧠 Model │ 📂 project │ 🌿 branch │ CTX NN% │ 📝 +156 -23 │ [⚡ │ 📋 N]
# CTX color: green <55%, yellow 55-69%, orange 70-84%, red 85%+
# Width-aware: drops low-priority segments when terminal is narrow.

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

# ── Collect task metrics ─────────────────────────────────
T_PHASE="" T_DONE=0 T_TOTAL=0 T_CURRENT="" T_BUGS=0 T_BUILD_STEP=""
TASK_FILE=""
for TF in "$CWD/.claude/tasks.json" "$PROJECT/.claude/tasks.json"; do
  [ -f "$TF" ] && TASK_FILE="$TF" && break
done
if [ -n "$TASK_FILE" ]; then
  # Read from cache (written by post-tasks-validate.sh on every tasks.json write)
  # Staleness check: if tasks.json is newer than cache, fall back to jq and refresh
  CACHE_FILE="${TASK_FILE%.json}.statusline.tsv"
  CACHE_FRESH=false
  if [ -f "$CACHE_FILE" ] && [ ! "$TASK_FILE" -nt "$CACHE_FILE" ]; then
    CACHE_FRESH=true
  fi
  if [ "$CACHE_FRESH" = true ]; then
    IFS=$'\t' read -r T_PHASE T_DONE T_TOTAL T_CURRENT T_BUGS T_BUILD_STEP < "$CACHE_FILE"
  else
    # Fallback: compute directly (cache missing or stale)
    IFS=$'\t' read -r T_PHASE T_DONE T_TOTAL T_CURRENT T_BUGS T_BUILD_STEP <<< \
      "$(jq -r '
        def nonempty: if . == "" then "-" else . end;
        ([.tasks[] | select(.type == "phase" and .status == "in_progress")] | first // {}) as $phase |
        ([.tasks[] | select(.status == "in_progress" and (.type == "task" or .type == "subtask"))] | first // {}) as $active |
        [
          ((($phase.subject // "" | split(":") | first) // "") | ltrimstr("Phase ") | nonempty),
          ([.tasks[] | select((.type == "task" or .type == "subtask") and .status == "completed")] | length),
          ([.tasks[] | select(.type == "task" or .type == "subtask")] | length),
          (($active.subject // "") | nonempty),
          ([.tasks[] | select(.stream == "bugs" and .status != "completed" and .status != "cancelled")] | length),
          (($active.build_step // "") | nonempty)
        ] | @tsv' "$TASK_FILE" 2>/dev/null)"
    # Strip placeholder dashes from jq nonempty helper
    [ "$T_PHASE" = "-" ] && T_PHASE=""
    [ "$T_CURRENT" = "-" ] && T_CURRENT=""
    [ "$T_BUILD_STEP" = "-" ] && T_BUILD_STEP=""
    # Refresh cache inline
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$T_PHASE" "$T_DONE" "$T_TOTAL" "$T_CURRENT" "$T_BUGS" "$T_BUILD_STEP" > "$CACHE_FILE" 2>/dev/null
  fi
fi

# ── Detect current job ───────────────────────────────────
# Priority: skill hint file > build_step > no active task
CURRENT_JOB=""
JOB_HINT_FILE="$HOME/.claude/statusline-job-hint"
if [ -f "$JOB_HINT_FILE" ]; then
  # Skill-written hint (expires after 10 min)
  HINT_AGE=$(( $(date +%s) - $(stat -c %Y "$JOB_HINT_FILE" 2>/dev/null || echo 0) ))
  if (( HINT_AGE < 600 )); then
    CURRENT_JOB=$(cat "$JOB_HINT_FILE" 2>/dev/null | head -1 | tr -d '[:space:]')
  fi
fi
if [ -z "$CURRENT_JOB" ]; then
  if [ -n "${T_BUILD_STEP:-}" ]; then
    CURRENT_JOB="BUILD"
  elif [ -z "${T_CURRENT:-}" ]; then
    CURRENT_JOB="DECIDE"
  fi
fi

# ── DECIDE-mode data (next unblocked + blocked count) ────
T_NEXT_UNBLOCKED="" T_BLOCKED_COUNT=0
if [ "$CURRENT_JOB" = "DECIDE" ] && [ -n "$TASK_FILE" ]; then
  IFS=$'\t' read -r T_NEXT_UNBLOCKED T_BLOCKED_COUNT <<< \
    "$(jq -r '
      [.tasks[] | select((.type == "task" or .type == "subtask") and .status == "pending")] as $pending |
      [$pending[] | select((.blocked_by // []) | length == 0)] as $unblocked |
      [($unblocked | first | .subject // ""), ($pending | length - ($unblocked | length))]
      | @tsv' "$TASK_FILE" 2>/dev/null)"
  T_NEXT_UNBLOCKED="${T_NEXT_UNBLOCKED:-}"
  T_BLOCKED_COUNT="${T_BLOCKED_COUNT:-0}"
fi

# ── Learning velocity (corrections + patterns) ──────────
LV_CORRECTIONS=0 LV_EDITS=0 LV_PATTERNS=0
# Find most recent session file
SESSION_JSONL=$(ls -t /tmp/brana-session-*.jsonl 2>/dev/null | head -1)
if [ -n "$SESSION_JSONL" ] && [ -f "$SESSION_JSONL" ]; then
  LV_CORRECTIONS=$(grep -c '"outcome":"correction"' "$SESSION_JSONL" 2>/dev/null || echo 0)
  LV_EDITS=$(grep -c '"tool":"Edit"\|"tool":"Write"' "$SESSION_JSONL" 2>/dev/null || echo 0)
fi
# Patterns stored today (memory files modified today)
MEMORY_DIR="$HOME/.claude/projects/-home-martineserios-enter-thebrana-thebrana/memory"
if [ -d "$MEMORY_DIR" ]; then
  LV_PATTERNS=$(find "$MEMORY_DIR" -name "*.md" -newer "$MEMORY_DIR/MEMORY.md" -mmin -720 -type f 2>/dev/null | wc -l | tr -d ' ')
fi

# ── Collect scheduler health ─────────────────────────────
S_OK=0 S_FAIL=0
SCHED_STATUS="$HOME/.claude/scheduler/last-status.json"
if [ -f "$SCHED_STATUS" ]; then
  IFS=$'\t' read -r S_OK S_FAIL <<< \
    "$(jq -r '[
      ([.[] | select(.status == "SUCCESS")] | length),
      ([.[] | select(.status == "FAILED" or .status == "TIMEOUT")] | length)
    ] | @tsv' "$SCHED_STATUS" 2>/dev/null)"
  S_OK=${S_OK:-0}; S_FAIL=${S_FAIL:-0}
fi

# ── Slow-cache signals (written by scheduled job) ───────
SC_KNOWLEDGE_DAYS=0 SC_PORTFOLIO=0
SLOW_CACHE="${BRANA_SLOW_CACHE_FILE:-$HOME/.claude/statusline-slow-cache.tsv}"
if [ -f "$SLOW_CACHE" ]; then
  IFS=$'\t' read -r SC_RUFLO_COUNT _SC_REINDEX SC_STALE SC_PORTFOLIO SC_KNOWLEDGE_DAYS _SC_TS < "$SLOW_CACHE"
  SC_KNOWLEDGE_DAYS=${SC_KNOWLEDGE_DAYS:-0}; SC_PORTFOLIO=${SC_PORTFOLIO:-0}
  SC_STALE=${SC_STALE:-0}; SC_RUFLO_COUNT=${SC_RUFLO_COUNT:-0}
fi

# ── Claude-flow metrics ─────────────────────────────────
CF_STR="" CF_AC=0 CF_TC=0
FD="$CWD/.claude-flow"
if [ -d "$FD" ] && [ -f "$FD/swarm-config.json" ]; then
  IFS=$'\t' read -r CF_STR CF_AC <<< \
    "$(jq -r '[(.defaultStrategy // ""), (.agentProfiles | length // 0)] | @tsv' \
      "$FD/swarm-config.json" 2>/dev/null)"
fi
if [ -d "$FD/tasks" ]; then
  CF_TC=$(find "$FD/tasks" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
fi

# ── Build segments per line ──────────────────────────────
# Line 1: Core orientation (model, project, branch, CTX, task, bugs, phase)
# Line 2: Intelligence signals (knowledge, portfolio, decay, learning, lines, scheduler)
# Each line has its own priority-based width dropping.

SEGS_L1=()  PRIO_L1=()
SEGS_L2=()  PRIO_L2=()

add_l1() { SEGS_L1+=("$1"); PRIO_L1+=("$2"); }
add_l2() { SEGS_L2+=("$1"); PRIO_L2+=("$2"); }

# ── Line 1: Core orientation ────────────────────────────

# Priority 11: Model (always keep)
add_l1 "🧠 ${B}${Cw}${MODEL}${R}" 11

# Priority 10: Project (always keep)
add_l1 " $S 📂 ${Cy}${PROJ_NAME}${R}" 10

# Priority 9: Branch (always keep)
[ -n "$BRANCH" ] && add_l1 " $S 🌿 ${Co}${BRANCH}${R}" 9

# Priority 8: CTX% (always keep)
add_l1 " $S ${CTX_SHOW}" 8

# Priority 7: Task context (job-adaptive)
if [ "$CURRENT_JOB" = "DECIDE" ]; then
  if [ -n "$T_NEXT_UNBLOCKED" ]; then
    NU="${T_NEXT_UNBLOCKED:0:25}"
    add_l1 " $S ${Cm}DECIDE${R} → ${Cw}${NU}${R}" 7
  else
    add_l1 " $S ${Cm}DECIDE${R}" 7
  fi
  if (( T_BLOCKED_COUNT > 0 )) 2>/dev/null; then
    add_l1 " ${D}(${T_BLOCKED_COUNT} blocked)${R}" 6
  fi
elif [ "$CURRENT_JOB" = "BUILD" ]; then
  if [ -n "$T_CURRENT" ]; then
    TC="${T_CURRENT:0:25}"
    add_l1 " $S ${Cm}BUILD${R} → ${Cw}${TC}${R}" 7
  fi
  if [ -n "${T_BUILD_STEP:-}" ]; then
    add_l1 " ${Cm}[${T_BUILD_STEP}]${R}" 6
  fi
else
  if [ -n "$T_CURRENT" ]; then
    TC="${T_CURRENT:0:25}"
    add_l1 " $S → ${Cw}${TC}${R}" 7
  fi
  if [ -n "${T_BUILD_STEP:-}" ]; then
    add_l1 " ${Cm}[${T_BUILD_STEP}]${R}" 6
  fi
fi

# Priority 5: Bug count
if (( T_BUGS > 0 )) 2>/dev/null; then
  add_l1 " $S 🐛 ${Cr}${T_BUGS} bugs${R}" 5
fi

# Priority 4: Phase progress
if [ -n "$T_PHASE" ] && (( T_TOTAL > 0 )); then
  add_l1 " $S 📋 ${Cy}Ph${T_PHASE}: ${T_DONE}/${T_TOTAL}${R}" 4
fi

# ── Line 2: Intelligence signals ─────────────────────────

# Priority 6: Knowledge freshness
if (( SC_KNOWLEDGE_DAYS > 0 )) 2>/dev/null; then
  if (( SC_KNOWLEDGE_DAYS >= 14 )); then
    add_l2 "📚 ${Co}knowledge: ${SC_KNOWLEDGE_DAYS}d ago${R}" 6
  else
    add_l2 "📚 ${D}knowledge: ${SC_KNOWLEDGE_DAYS}d ago${R}" 6
  fi
fi

# Priority 4: Learning velocity (corrections — show rate only when high)
if (( LV_EDITS > 0 )) 2>/dev/null && (( LV_CORRECTIONS > 0 )) 2>/dev/null; then
  LV_RATE=$(( LV_CORRECTIONS * 100 / LV_EDITS ))
  if (( LV_RATE >= 50 )); then
    add_l2 " $S 🔄 ${Cr}${LV_RATE}% corrections${R}" 4
  elif (( LV_RATE >= 30 )); then
    add_l2 " $S 🔄 ${Co}${LV_RATE}% corrections${R}" 4
  fi
fi
if (( LV_PATTERNS > 0 )) 2>/dev/null; then
  add_l2 " $S 🧩 ${Cg}patterns: ${LV_PATTERNS}${R}" 4
fi

# Priority 3: Lines added/removed
add_l2 " $S 📝 ${Cg}+${LA}${R} ${Cr}-${LD}${R}" 3

# Priority 2: Scheduler health
if (( S_FAIL > 0 )); then
  add_l2 " $S 📅 ${D}scheduler:${R} ${Cg}${S_OK}✓${R} ${Cr}${S_FAIL}✗${R}" 2
elif (( S_OK > 0 )); then
  add_l2 " $S 📅 ${D}scheduler:${R} ${Cg}${S_OK}✓${R}" 2
fi

# Priority 1: Claude-flow (rare)
[ -n "$CF_STR" ] && add_l2 " $S ⚡ ${Cm}${CF_STR}${R}" 1
(( CF_AC > 0 )) 2>/dev/null && add_l2 " 🤖 ${Cm}${CF_AC}${R}" 1
(( CF_TC > 0 )) && add_l2 " $S 📋 ${Cy}${CF_TC}${R}" 1

# ── Width detection + progressive dropping ───────────────
MAX_COLS="${BRANA_STATUSLINE_COLS:-}"
if [ -z "$MAX_COLS" ]; then
  MAX_COLS=$(tput cols 2>/dev/null || echo "")
fi

_visible_len() {
  printf '%b' "$1" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\n' | wc -m
}

# Render one line with width-aware dropping
_render_line() {
  local -n _segs=$1
  local -n _prios=$2

  if [ ${#_segs[@]} -eq 0 ]; then return; fi

  if [ -n "$MAX_COLS" ] && (( MAX_COLS > 0 )); then
    # Sort by priority descending
    local SORTED=()
    for i in "${!_prios[@]}"; do SORTED+=("$i"); done
    for ((i = 1; i < ${#SORTED[@]}; i++)); do
      local key=${SORTED[$i]} j=$((i - 1))
      while (( j >= 0 )) && (( _prios[SORTED[j]] < _prios[key] )); do
        SORTED[$((j + 1))]=${SORTED[$j]}; j=$((j - 1))
      done
      SORTED[$((j + 1))]=$key
    done

    local LEN=0 INCLUDED=()
    for idx in "${SORTED[@]}"; do
      local seg_len=$(_visible_len "${_segs[$idx]}")
      if (( LEN + seg_len <= MAX_COLS )); then
        INCLUDED+=("$idx"); LEN=$((LEN + seg_len))
      fi
    done

    for i in "${!_segs[@]}"; do
      for inc in "${INCLUDED[@]}"; do
        [ "$i" = "$inc" ] && { printf '%b' "${_segs[$i]}"; break; }
      done
    done
  else
    for seg in "${_segs[@]}"; do printf '%b' "$seg"; done
  fi
  echo
}

_render_line SEGS_L1 PRIO_L1
# Only print line 2 if it has segments
if [ ${#SEGS_L2[@]} -gt 0 ]; then
  _render_line SEGS_L2 PRIO_L2
fi
