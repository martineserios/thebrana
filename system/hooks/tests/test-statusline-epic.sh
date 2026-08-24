#!/usr/bin/env bash
# Tests for statusline epic resolution (t-2467, revised ADR-088/t-3196).
#
# The epic segment comes from exactly two sources now, no config file
# involved: (1) the 3-segment branch convention ({epic}/{work-type}/t-NNN-
# slug), or (2) the most-recently-started in_progress task's flat `.epic`
# field (the pre-v3 schema client/venture projects use) when the branch
# doesn't carry a 3-segment epic. thebrana's own v3 parent-chain epics are
# not resolved here (hot-path render, not the place for a multi-hop lookup)
# and simply show no epic on dev/main, same as before.
#
# ADR-088 (t-3196): the static tasks-config.json active_epic fallback this
# test file used to exercise is retired entirely, along with the shared
# config file itself. No config path — local, global, or thebrana's
# system/state/ layout — is ever read for this anymore.

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

# A fake HOME carrying a leftover global active_epic (simulating a pre-ADR-088
# config that was never cleaned up). Nothing may ever read it.
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

echo "=== statusline epic resolution (t-2467, revised t-3196) ==="

# T1 -- branch-derived epic still works
R=$(make_repo t1 "myepic/feat/t-1-do-thing")
[ "$(epic_of "$R")" = "myepic" ]; check "T1: 3-segment branch yields branch epic" $?

# T2 -- no config, no in_progress task -> no epic segment at all
R=$(make_repo t2 dev)
[ -z "$(epic_of "$R")" ]; check "T2: nothing to resolve -> no epic segment" $?

# T3 -- precedence: branch epic wins over the dynamic in_progress task epic
# when both are available (branch check happens first, unconditionally).
R=$(make_repo t3 "branchepic/feat/t-9-x")
mkdir -p "$R/.claude"
printf '{"tasks":[{"id":"t-1","status":"in_progress","epic":"dyn-epic","started":"2026-08-01"}]}\n' \
    > "$R/.claude/tasks.json"
[ "$(epic_of "$R")" = "branchepic" ]; check "T3: branch epic wins over dynamic in_progress epic" $?

# T4 -- nothing to resolve: slot must be omitted entirely (duplicate of T2's
# intent kept for numbering stability with the pre-t-3196 suite)
R=$(make_repo t4 dev)
[ -z "$(epic_of "$R")" ]; check "T4: no tasks.json -> no epic segment" $?

# T5 -- a leftover/malformed tasks-config.json anywhere must be inert: never
# read, never causes an error, never surfaces its value.
R=$(make_repo t5 dev)
mkdir -p "$R/.claude"
printf '{ this is not json\n' > "$R/.claude/tasks-config.json"
OUT=$(printf '{"model":{"display_name":"T"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":10}}' "$R" \
    | HOME="$TMP/fakehome" bash "$STATUSLINE" 2>/dev/null); RC=$?
[ "$RC" = "0" ] && [ -z "$(epic_of "$R")" ]
check "T5: malformed tasks-config.json is inert, exit 0" $?

# T6 -- thebrana's own system/state/tasks-config.json layout is equally inert
R=$(make_repo t6 dev)
mkdir -p "$R/system/state"
printf '{"active_epic":"harness-core"}\n' > "$R/system/state/tasks-config.json"
[ -z "$(epic_of "$R")" ]; check "T6: system/state/ config layout never read" $?

# T7 -- neither local nor global tasks-config.json is ever read (strengthened
# from the pre-t-3196 global-only guard: local active_epic must not surface
# either, since the fallback that used to read it no longer exists).
R=$(make_repo t7 dev)
mkdir -p "$R/.claude"
printf '{"active_epic":"LOCAL-LEAK"}\n' > "$R/.claude/tasks-config.json"
OUT="$(epic_of "$R")"
[ "$OUT" != "GLOBAL-LEAK" ] && [ "$OUT" != "LOCAL-LEAK" ] && [ -z "$OUT" ]
check "T7: neither local nor global tasks-config.json ever surfaces" $?

# T8 -- a single in_progress task's dynamic .epic field renders on dev
R=$(make_repo t8 dev)
mkdir -p "$R/.claude"
printf '{"tasks":[{"id":"t-1","status":"in_progress","epic":"dyn-epic","started":"2026-08-01"}]}\n' \
    > "$R/.claude/tasks.json"
[ "$(epic_of "$R")" = "dyn-epic" ]; check "T8: single in_progress task's dynamic epic renders" $?

# T9 -- among several in_progress tasks, the latest `started` timestamp wins
R=$(make_repo t9 dev)
mkdir -p "$R/.claude"
printf '{"tasks":[
  {"id":"t-1","status":"in_progress","epic":"older-epic","started":"2026-07-01"},
  {"id":"t-2","status":"in_progress","epic":"newer-epic","started":"2026-08-01"},
  {"id":"t-3","status":"completed","epic":"done-epic","started":"2026-08-05"}
]}\n' > "$R/.claude/tasks.json"
[ "$(epic_of "$R")" = "newer-epic" ]; check "T9: latest-started in_progress task wins (status filter applied)" $?

# T10 -- in_progress task with no epic field, and nothing else to fall back
# to -> no epic segment (the static fallback that used to catch this is gone)
R=$(make_repo t10 dev)
mkdir -p "$R/.claude"
printf '{"tasks":[{"id":"t-1","status":"in_progress","started":"2026-08-01"}]}\n' \
    > "$R/.claude/tasks.json"
[ -z "$(epic_of "$R")" ]; check "T10: no-epic in_progress task, no fallback left -> no epic segment" $?

# T11 -- malformed tasks.json degrades silently to no epic segment, exit 0
# (previously fell back to active_epic; that fallback no longer exists)
R=$(make_repo t11 dev)
mkdir -p "$R/.claude"
printf '{ this is not json\n' > "$R/.claude/tasks.json"
OUT=$(printf '{"model":{"display_name":"T"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":10}}' "$R" \
    | HOME="$TMP/fakehome" bash "$STATUSLINE" 2>/dev/null); RC=$?
[ "$RC" = "0" ] && [ -z "$(epic_of "$R")" ]
check "T11: malformed tasks.json -> no epic segment, exit 0" $?

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

# T13 -- the jq-scan pre-check (t-2641) must match pretty-printed JSON
# (`"epic": "value"`, a space after the colon), not just compact JSON
# (`"epic":"value"`) -- caught live: this exact gap silently regressed
# proyecto_anita, the project the dynamic fallback exists for, because its
# tasks.json is pretty-printed and thebrana's own is compact.
R=$(make_repo t13 dev)
mkdir -p "$R/.claude"
printf '{\n  "tasks": [\n    {\n      "id": "t-1",\n      "status": "in_progress",\n      "epic": "pretty-epic",\n      "started": "2026-08-05"\n    }\n  ]\n}\n' \
    > "$R/.claude/tasks.json"
[ "$(epic_of "$R")" = "pretty-epic" ]; check "T13: pre-check matches pretty-printed JSON (space after colon)" $?

# T14 -- pre-check correctly skips the jq scan (no epic to find) when
# tasks.json has no "epic" key at all, not even null -- the shape thebrana's
# own tasks.json actually has (v3 schema, key entirely absent). No fallback
# left to catch this, so the result is simply no epic segment.
R=$(make_repo t14 dev)
mkdir -p "$R/.claude"
printf '{"tasks":[{"id":"t-1","status":"in_progress","started":"2026-08-05"}]}\n' \
    > "$R/.claude/tasks.json"
[ -z "$(epic_of "$R")" ]; check "T14: no epic key anywhere -> pre-check skips jq, no epic segment" $?

echo ""
echo "--- boundaries ---"

# B1 -- CC is opened inside subdirectories too; resolution is GIT_ROOT-relative
# (retargeted from active_epic config to the dynamic in_progress task path —
# the only remaining non-branch source).
R=$(make_repo b1 dev)
mkdir -p "$R/.claude" "$R/deep/nested/dir"
printf '{"tasks":[{"id":"t-1","status":"in_progress","epic":"from-subdir","started":"2026-08-01"}]}\n' \
    > "$R/.claude/tasks.json"
[ "$(epic_of "$R/deep/nested/dir")" = "from-subdir" ]; check "B1: resolves from a subdirectory" $?

# B2 -- outside any git repo: no GIT_ROOT, must not error or emit an epic,
# even with a dynamic in_progress task sitting in an unreachable .claude/
NOGIT="$TMP/nogit"; mkdir -p "$NOGIT/.claude"
printf '{"tasks":[{"id":"t-1","status":"in_progress","epic":"not-a-repo","started":"2026-08-01"}]}\n' \
    > "$NOGIT/.claude/tasks.json"
[ -z "$(epic_of "$NOGIT")" ]; check "B2: non-git dir -> no epic segment" $?

# B3 -- the output is printf '%b', so backslash escapes in an epic value
# would be interpreted; a newline would break the single-line statusline
# contract. Retargeted to the dynamic task .epic field (the only source that
# can still carry an attacker/typo-controlled string).
R=$(make_repo b3 dev)
mkdir -p "$R/.claude"
printf '{"tasks":[{"id":"t-1","status":"in_progress","epic":"bad\\\\nvalue","started":"2026-08-01"}]}\n' \
    > "$R/.claude/tasks.json"
LINES=$(printf '{"model":{"display_name":"T"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":10}}' "$R" \
    | HOME="$TMP/fakehome" bash "$STATUSLINE" 2>/dev/null | wc -l)
[ "$LINES" = "1" ]; check "B3: escape sequence in dynamic epic stays single-line" $?

# B4 -- same contract for a real embedded newline (jq -r emits it verbatim)
R=$(make_repo b4 dev)
mkdir -p "$R/.claude"
printf '{"tasks":[{"id":"t-1","status":"in_progress","epic":"bad\\nvalue","started":"2026-08-01"}]}\n' \
    > "$R/.claude/tasks.json"
LINES=$(printf '{"model":{"display_name":"T"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":10}}' "$R" \
    | HOME="$TMP/fakehome" bash "$STATUSLINE" 2>/dev/null | wc -l)
[ "$LINES" = "1" ]; check "B4: literal newline in dynamic epic stays single-line" $?

# B5 -- a raw control byte delivered via a JSON  (ESC) escape has no
# backslash character left after jq decodes it, so the backslash-strip alone
# can't catch it; the scrub must also strip raw control bytes directly
# (t-2639 challenger, via the dynamic task .epic field — the only remaining
# source since the config-fed B8 case was retired with the config fallback).
R=$(make_repo b5 dev)
mkdir -p "$R/.claude"
printf '{"tasks":[{"id":"t-1","status":"in_progress","epic":"bad\\u001bvalue","started":"2026-08-01"}]}\n' \
    > "$R/.claude/tasks.json"
LINES=$(printf '{"model":{"display_name":"T"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":10}}' "$R" \
    | HOME="$TMP/fakehome" bash "$STATUSLINE" 2>/dev/null | wc -l)
[ "$LINES" = "1" ] && [ "$(epic_of "$R")" = "badvalue" ]
check "B5: raw ESC byte in dynamic task .epic field is stripped" $?

echo ""; echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
