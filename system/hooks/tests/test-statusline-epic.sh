#!/usr/bin/env bash
# Tests for statusline epic resolution (t-2467).
#
# The epic segment used to come only from thebrana's 3-segment branch
# convention ({epic}/{work-type}/t-NNN-slug), so it never rendered in
# clients/ventures, which use 2-segment branches and sit on main/dev.
# A project-local active_epic fallback fills that gap.
#
# ADR-066: active_epic is project-scoped with exactly one authoritative
# source -- the resolving project's own config. The global
# ~/.claude/tasks-config.json is NEVER a valid source for this key (T7).
#
# Tests:
#   T1 -- 3-segment task branch yields the branch epic
#   T2 -- on dev with project-local .claude/ active_epic -> that epic
#   T3 -- branch epic wins over active_epic (precedence unchanged)
#   T4 -- no config -> no epic segment
#   T5 -- malformed config -> no epic segment, still exits 0
#   T6 -- thebrana layout (system/state/) active_epic -> that epic
#   T7 -- global ~/.claude/tasks-config.json is never read

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATUSLINE="$SCRIPT_DIR/../../statusline.sh"
PASS=0; FAIL=0; TOTAL=0

check() {
    local desc="$1" ok="$2"
    TOTAL=$((TOTAL+1))
    if [ "$ok" = "0" ]; then PASS=$((PASS+1)); echo "  PASS: $desc"
    else FAIL=$((FAIL+1)); echo "  FAIL: $desc"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A fake HOME carrying a global active_epic. Nothing may ever read it (T7).
mkdir -p "$TMP/fakehome/.claude"
printf '{"active_epic":"GLOBAL-LEAK","theme":"emoji"}\n' \
    > "$TMP/fakehome/.claude/tasks-config.json"

# make_repo <name> <branch> -- bare-bones git repo on the given branch.
# No commits needed: show-toplevel and branch --show-current both work on an
# unborn branch, which keeps the fixtures fast and identity-config free.
make_repo() {
    local dir="$TMP/$1"
    mkdir -p "$dir"
    git -C "$dir" init -q -b "$2" >/dev/null 2>&1
    echo "$dir"
}

# epic_of <repo-dir> -- render the statusline and echo the epic segment
# (empty when the slot is not emitted). HOME is redirected so any accidental
# read of the global config would surface as GLOBAL-LEAK.
epic_of() {
    local dir="$1" out
    out=$(printf '{"model":{"display_name":"T"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":10}}' "$dir" \
        | HOME="$TMP/fakehome" bash "$STATUSLINE" 2>/dev/null \
        | sed -e 's/\x1b\[[0-9;]*m//g')
    # Slot renders as: <sep> 🎯 <epic> <sep> CTX ...
    echo "$out" | grep -o '🎯 [^│]*' | sed -e 's/^🎯 //' -e 's/[[:space:]]*$//'
}

echo "=== statusline epic resolution (t-2467) ==="

# T1 -- branch-derived epic still works (no config present)
R=$(make_repo t1 "myepic/feat/t-1-do-thing")
[ "$(epic_of "$R")" = "myepic" ]; check "T1: 3-segment branch yields branch epic" $?

# T2 -- the gap this task closes: 2-segment convention, sitting on dev
R=$(make_repo t2 dev)
mkdir -p "$R/.claude"
printf '{"active_epic":"alpha-epic","theme":"emoji"}\n' > "$R/.claude/tasks-config.json"
[ "$(epic_of "$R")" = "alpha-epic" ]; check "T2: project-local .claude/ active_epic on dev" $?

# T3 -- precedence: branch epic must win when both are available
R=$(make_repo t3 "branchepic/feat/t-9-x")
mkdir -p "$R/.claude"
printf '{"active_epic":"config-epic"}\n' > "$R/.claude/tasks-config.json"
[ "$(epic_of "$R")" = "branchepic" ]; check "T3: branch epic wins over active_epic" $?

# T4 -- nothing to resolve: slot must be omitted entirely
R=$(make_repo t4 dev)
[ -z "$(epic_of "$R")" ]; check "T4: no config -> no epic segment" $?

# T5 -- malformed JSON must degrade silently, not error or leak jq noise
R=$(make_repo t5 dev)
mkdir -p "$R/.claude"
printf '{ this is not json\n' > "$R/.claude/tasks-config.json"
OUT=$(printf '{"model":{"display_name":"T"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":10}}' "$R" \
    | HOME="$TMP/fakehome" bash "$STATUSLINE" 2>/dev/null); RC=$?
[ "$RC" = "0" ] && [ -z "$(epic_of "$R")" ]
check "T5: malformed config -> no epic, exit 0" $?

# T6 -- thebrana keeps its config at system/state/, not .claude/
R=$(make_repo t6 dev)
mkdir -p "$R/system/state"
printf '{"active_epic":"harness-core"}\n' > "$R/system/state/tasks-config.json"
[ "$(epic_of "$R")" = "harness-core" ]; check "T6: system/state/ layout active_epic" $?

# T7 -- ADR-066 guard: a global value must never surface
R=$(make_repo t7 dev)
[ "$(epic_of "$R")" != "GLOBAL-LEAK" ]; check "T7: global ~/.claude config never read" $?

# T8 -- dynamic derivation (t-2639): most-recently-started in_progress task's
# .epic field wins over a stale static active_epic on main/dev.
R=$(make_repo t8 dev)
mkdir -p "$R/.claude"
printf '{"active_epic":"stale-epic"}\n' > "$R/.claude/tasks-config.json"
printf '{"tasks":[{"id":"t-1","status":"in_progress","epic":"dyn-epic","started":"2026-08-01"}]}\n' \
    > "$R/.claude/tasks.json"
[ "$(epic_of "$R")" = "dyn-epic" ]; check "T8: dynamic in_progress epic wins over stale active_epic" $?

# T9 -- among several in_progress tasks, the latest `started` timestamp wins
R=$(make_repo t9 dev)
mkdir -p "$R/.claude"
printf '{"tasks":[
  {"id":"t-1","status":"in_progress","epic":"older-epic","started":"2026-07-01"},
  {"id":"t-2","status":"in_progress","epic":"newer-epic","started":"2026-08-01"},
  {"id":"t-3","status":"completed","epic":"done-epic","started":"2026-08-05"}
]}\n' > "$R/.claude/tasks.json"
[ "$(epic_of "$R")" = "newer-epic" ]; check "T9: latest-started in_progress task wins (status filter applied)" $?

# T10 -- in_progress tasks with no epic field are skipped; static active_epic
# is still the fallback when none of them carry one
R=$(make_repo t10 dev)
mkdir -p "$R/.claude"
printf '{"active_epic":"fallback-epic"}\n' > "$R/.claude/tasks-config.json"
printf '{"tasks":[{"id":"t-1","status":"in_progress","started":"2026-08-01"}]}\n' \
    > "$R/.claude/tasks.json"
[ "$(epic_of "$R")" = "fallback-epic" ]; check "T10: no-epic in_progress task falls back to active_epic" $?

# T11 -- malformed tasks.json degrades silently to the static fallback, exit 0
R=$(make_repo t11 dev)
mkdir -p "$R/.claude"
printf '{"active_epic":"fallback-epic"}\n' > "$R/.claude/tasks-config.json"
printf '{ this is not json\n' > "$R/.claude/tasks.json"
OUT=$(printf '{"model":{"display_name":"T"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":10}}' "$R" \
    | HOME="$TMP/fakehome" bash "$STATUSLINE" 2>/dev/null); RC=$?
[ "$RC" = "0" ] && [ "$(epic_of "$R")" = "fallback-epic" ]
check "T11: malformed tasks.json -> falls back to active_epic, exit 0" $?

# T12 -- same-day tie among in_progress tasks (production `.started` is
# date-only, so this is a realistic occurrence, not a rare edge, t-2639
# challenger): higher numeric task id wins, not array-insertion order.
R=$(make_repo t12 dev)
mkdir -p "$R/.claude"
printf '{"tasks":[
  {"id":"t-2076","status":"in_progress","epic":"higher-id-epic","started":"2026-08-05"},
  {"id":"t-2065","status":"in_progress","epic":"lower-id-epic","started":"2026-08-05"}
]}\n' > "$R/.claude/tasks.json"
[ "$(epic_of "$R")" = "higher-id-epic" ]; check "T12: same-day tie breaks by higher numeric task id" $?

echo ""
echo "--- boundaries ---"

# B1 -- empty-string active_epic must not render an empty slot
R=$(make_repo b1 dev)
mkdir -p "$R/.claude"
printf '{"active_epic":""}\n' > "$R/.claude/tasks-config.json"
[ -z "$(epic_of "$R")" ]; check "B1: empty active_epic -> no epic segment" $?

# B2 -- explicit JSON null must behave like absent
R=$(make_repo b2 dev)
mkdir -p "$R/.claude"
printf '{"active_epic":null}\n' > "$R/.claude/tasks-config.json"
[ -z "$(epic_of "$R")" ]; check "B2: null active_epic -> no epic segment" $?

# B3 -- .claude/ exists but lacks the key; system/state/ has it. The loop must
# fall through to the second path rather than stopping at the first file found.
R=$(make_repo b3 dev)
mkdir -p "$R/.claude" "$R/system/state"
printf '{"theme":"emoji"}\n' > "$R/.claude/tasks-config.json"
printf '{"active_epic":"second-path"}\n' > "$R/system/state/tasks-config.json"
[ "$(epic_of "$R")" = "second-path" ]; check "B3: keyless first config falls through to second" $?

# B4 -- CC is opened inside subdirectories too; resolution is GIT_ROOT-relative
R=$(make_repo b4 dev)
mkdir -p "$R/.claude" "$R/deep/nested/dir"
printf '{"active_epic":"from-subdir"}\n' > "$R/.claude/tasks-config.json"
[ "$(epic_of "$R/deep/nested/dir")" = "from-subdir" ]; check "B4: resolves from a subdirectory" $?

# B5 -- outside any git repo: no GIT_ROOT, must not error or emit an epic
NOGIT="$TMP/nogit"; mkdir -p "$NOGIT/.claude"
printf '{"active_epic":"not-a-repo"}\n' > "$NOGIT/.claude/tasks-config.json"
[ -z "$(epic_of "$NOGIT")" ]; check "B5: non-git dir -> no epic segment" $?

# B6 -- the output is printf '%b', so backslash escapes in a config value would
# be interpreted; a newline would break the single-line statusline contract.
R=$(make_repo b6 dev)
mkdir -p "$R/.claude"
printf '{"active_epic":"bad\\\\nvalue"}\n' > "$R/.claude/tasks-config.json"
LINES=$(printf '{"model":{"display_name":"T"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":10}}' "$R" \
    | HOME="$TMP/fakehome" bash "$STATUSLINE" 2>/dev/null | wc -l)
[ "$LINES" = "1" ]; check "B6: escape sequence in active_epic stays single-line" $?

# B7 -- same contract for a real embedded newline (jq -r emits it verbatim)
R=$(make_repo b7 dev)
mkdir -p "$R/.claude"
printf '{"active_epic":"bad\\nvalue"}\n' > "$R/.claude/tasks-config.json"
LINES=$(printf '{"model":{"display_name":"T"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":10}}' "$R" \
    | HOME="$TMP/fakehome" bash "$STATUSLINE" 2>/dev/null | wc -l)
[ "$LINES" = "1" ]; check "B7: literal newline in active_epic stays single-line" $?

# B8 -- a raw control byte delivered via a JSON \u001b (ESC) escape has no
# backslash character left after jq decodes it, so the backslash-strip alone
# can't catch it; the scrub must also strip raw control bytes directly
# (t-2639 challenger: pre-existing gap on active_epic, now closed).
R=$(make_repo b8 dev)
mkdir -p "$R/.claude"
printf '{"active_epic":"bad\\u001bvalue"}\n' > "$R/.claude/tasks-config.json"
LINES=$(printf '{"model":{"display_name":"T"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":10}}' "$R" \
    | HOME="$TMP/fakehome" bash "$STATUSLINE" 2>/dev/null | wc -l)
[ "$LINES" = "1" ] && [ "$(epic_of "$R")" = "badvalue" ]
check "B8: raw ESC byte (JSON \\u001b escape) in active_epic is stripped" $?

# B9 -- same class, but through the new dynamic source (t-2639 widened the
# shared scrub's reach to every task's .epic field, any write path).
R=$(make_repo b9 dev)
mkdir -p "$R/.claude"
printf '{"tasks":[{"id":"t-1","status":"in_progress","epic":"bad\\u001bvalue","started":"2026-08-01"}]}\n' \
    > "$R/.claude/tasks.json"
LINES=$(printf '{"model":{"display_name":"T"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":10}}' "$R" \
    | HOME="$TMP/fakehome" bash "$STATUSLINE" 2>/dev/null | wc -l)
[ "$LINES" = "1" ] && [ "$(epic_of "$R")" = "badvalue" ]
check "B9: raw ESC byte in dynamic task .epic field is stripped" $?

echo ""; echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
