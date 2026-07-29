#!/usr/bin/env bash
# check-worktree-divergence.sh — live worktrees vs. their task records (t-2545).
#
# Usage: check-worktree-divergence.sh [repo-root]
#   exit 0 = no contradictions (omissions may still be reported)
#   exit 1 = at least one contradiction, or the task schema drifted
#
# WHY THIS EXISTS. Three signals claim to say what work is in flight — the WIP
# cap, status:in_progress, and live worktrees — and t-2541 measured them
# disagreeing in every direction. On 2026-07-29 only 2 of 5 worktrees agreed
# with their task record: one belonged to a task completed 39 days earlier, one
# named a branch that does not exist, one had no branch recorded at all. The
# 39-day orphan was found by eye. Nothing checked for it: t-2541 grepped all 67
# existing checks and session-end-drift.sh and found zero coverage.
#
# The repo is authoritative; the task field is a cache. In every divergence
# observed, the repo was right and the field was stale, absent, or fictional.
#
# THIS NEVER REPAIRS ANYTHING. It reports and requires a human. Auto-correcting
# would have rewritten t-2173's branch field to match the repo and destroyed the
# evidence the two had disagreed for 37 days — right in all four observed cases
# and still wrong, because it erases the drift rate.
#
# Severity (spec D2 — contradictions fail, omissions warn):
#   ORPHAN, FIELD-MISMATCH, LOOKUP-FAILED -> the record asserts something false
#   FIELD-NULL, IDLE, NO-TASK-ID, DETACHED -> the record is merely incomplete
#
# NOTE THE ABSENT `-e`. Copied from check-adr-uniqueness.sh:20, deliberately not
# from validate.sh:2 (`set -euo pipefail`). This loop makes two subprocess calls
# per worktree; under `-e` the first non-zero exit aborts mid-iteration and every
# later worktree goes silently unexamined — the same fail-open this check exists
# to catch, arriving one level up.
set -uo pipefail

# Threshold justified by git-discipline.md §Keep branches short-lived ("Features:
# days. Fixes: hours."), not fitted to the sample. The 2026-07-29 distribution
# (0,0,0,4 then 37,39) has an empty span between 5 and 36, so it corroborates any
# value in that range and can discriminate none of them. Revisit if IDLE fires on
# the same worktree across 3+ consecutive validate runs.
IDLE_THRESHOLD_DAYS="${IDLE_THRESHOLD_DAYS:-14}"

ROOT="${1:-}"
if [ -z "$ROOT" ]; then
    ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT="."
fi

if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    echo "check-worktree-divergence: not a git repository: $ROOT" >&2
    exit 1
fi

CONTRADICTIONS=0
NOW=$(date +%s)

# Read one field. Prints the JSON-unquoted value, including the literal `null`.
#
# Deliberately does NOT collapse null to "" the way _epic_field() in
# epic-ancestor-walk.md does. That collapse is right there (both answers mean
# "keep walking") and wrong here, where FIELD-NULL is a distinct finding.
# Returns 1 only on a genuine lookup failure — never confuse the two (t-2487).
_field() {
    local out
    out=$(brana backlog get "$1" --field "$2" 2>/dev/null) || return 1
    [ -z "$out" ] && return 1
    out=${out#\"}; out=${out%\"}
    printf '%s' "$out"
}

# Age in whole days of the worktree's HEAD commit; prints "unknown" if the
# lookup fails, never 0 — a failed lookup must not read as "fresh".
_idle_days() {
    local ts
    ts=$(git -C "$1" log -1 --format=%ct 2>/dev/null) || { printf 'unknown'; return; }
    [ -z "$ts" ] && { printf 'unknown'; return; }
    printf '%s' $(( (NOW - ts) / 86400 ))
}

report_fail() { echo "$1"; CONTRADICTIONS=$((CONTRADICTIONS + 1)); }
report_warn() { echo "$1"; }

# ── Collect worktrees ────────────────────────────────────────────────────────
# The main checkout is listed first by `git worktree list` and is excluded: it
# tracks the integration branch, carries no t-NNN, and is not work in flight.
MAIN_WT=$(git -C "$ROOT" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')

WT_PATHS=()
WT_BRANCHES=()
_cur_path=""
_cur_branch=""
_flush() {
    [ -z "$_cur_path" ] && return 0
    if [ "$_cur_path" != "$MAIN_WT" ]; then
        WT_PATHS+=("$_cur_path")
        WT_BRANCHES+=("$_cur_branch")
    fi
    _cur_path=""; _cur_branch=""
}
while IFS= read -r line; do
    case "$line" in
        worktree\ *) _flush; _cur_path="${line#worktree }" ;;
        branch\ *)   _cur_branch="${line#branch refs/heads/}" ;;
        detached)    _cur_branch="" ;;
    esac
done < <(git -C "$ROOT" worktree list --porcelain 2>/dev/null)
_flush

if [ "${#WT_PATHS[@]}" -eq 0 ]; then
    echo "no worktrees besides the main checkout"
    exit 0
fi

# ── Schema self-test ─────────────────────────────────────────────────────────
# `brana backlog get --field X` prints `null` at exit 0 both when X is null and
# when X is not a key at all — verified 2026-07-29: `--field totally_bogus_field`
# returns null, exit 0. Without this guard, renaming `branch` or `status` (this
# repo has retired backlog fields three times: Checks 62/63/64) would classify
# every worktree FIELD-NULL forever, with no crash and no signal.
#
# Probe the first task id that resolves; skip silently if none do (a tree of
# unbranched or ghost worktrees is a legitimate state, checked below).
_probe=""
for i in "${!WT_PATHS[@]}"; do
    _b="${WT_BRANCHES[$i]}"
    _t=$(printf '%s' "$_b" | grep -oE 't-[0-9]+' | head -1)
    [ -z "$_t" ] && continue
    if _obj=$(brana backlog get "$_t" 2>/dev/null); then _probe="$_t"; break; fi
done
if [ -n "$_probe" ]; then
    for _key in status branch; do
        if ! printf '%s' "$_obj" | grep -q "\"$_key\""; then
            echo "schema drift: field '$_key' is not present on task $_probe" >&2
            echo "  the check reads '$_key' to classify divergence; without it every" >&2
            echo "  worktree would be misreported. Update this script to the new field name." >&2
            exit 1
        fi
    done
fi

# ── Classify ─────────────────────────────────────────────────────────────────
for i in "${!WT_PATHS[@]}"; do
    wt="${WT_PATHS[$i]}"
    branch="${WT_BRANCHES[$i]}"
    name=$(basename "$wt")

    if [ -z "$branch" ]; then
        report_warn "  DETACHED       $name — worktree has no branch; cannot attribute to a task"
        continue
    fi

    tid=$(printf '%s' "$branch" | grep -oE 't-[0-9]+' | head -1)
    if [ -z "$tid" ]; then
        report_warn "  NO-TASK-ID     $name ($branch) — branch carries no t-NNN"
        continue
    fi

    if ! status=$(_field "$tid" status); then
        report_fail "  LOOKUP-FAILED  $name ($branch) — $tid could not be read from the backlog"
        continue
    fi

    idle=$(_idle_days "$wt")
    [ "$idle" = "unknown" ] && idle_txt="idle unknown" || idle_txt="idle ${idle}d"

    # ORPHAN suppresses this worktree's other categories: once the task is
    # closed, the state of its branch field is moot, and three findings for one
    # problem inflates the count. The idle age is kept inline — a 39-day orphan
    # is a different problem from a 1-day one.
    case "$status" in
        completed|cancelled)
            report_fail "  ORPHAN         $name ($branch) — $tid is $status, worktree still live ($idle_txt)"
            continue
            ;;
    esac

    if ! field_branch=$(_field "$tid" branch); then
        report_fail "  LOOKUP-FAILED  $name ($branch) — $tid branch field could not be read"
        continue
    fi

    if [ "$field_branch" = "null" ] || [ -z "$field_branch" ]; then
        report_warn "  FIELD-NULL     $name ($branch) — $tid records no branch"
    elif [ "$field_branch" != "$branch" ]; then
        report_fail "  FIELD-MISMATCH $name — worktree is on '$branch', $tid records '$field_branch'"
    fi

    if [ "$status" = "in_progress" ] && [ "$idle" != "unknown" ] \
       && [ "$idle" -gt "$IDLE_THRESHOLD_DAYS" ]; then
        report_warn "  IDLE           $name ($branch) — $tid in_progress, last commit ${idle}d ago (>${IDLE_THRESHOLD_DAYS}d)"
    fi
done

# ── Informational: declared in flight, but no worktree ───────────────────────
# NOT a failure and NOT a warning. Unbranched work is legitimate — research,
# capture-in-the-moment, edits in the main checkout — and is exactly why t-2541
# kept declared state as a second signal instead of deriving alone.
if _ip=$(brana backlog query --status in_progress --output json 2>/dev/null); then
    _seen=$(printf '%s\n' "${WT_BRANCHES[@]}")
    _first=1
    while IFS= read -r t; do
        [ -z "$t" ] && continue
        if ! printf '%s' "$_seen" | grep -q "$t"; then
            if [ "$_first" = 1 ]; then
                echo "  (info) in_progress with no worktree — not a failure:"
                _first=0
            fi
            echo "  (info)   $t"
        fi
    done < <(printf '%s' "$_ip" | grep -oE '"id":"t-[0-9]+"' | cut -d'"' -f4)
fi

[ "$CONTRADICTIONS" -eq 0 ] || exit 1
exit 0
