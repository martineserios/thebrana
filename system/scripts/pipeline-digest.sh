#!/usr/bin/env bash
# pipeline-digest.sh — L0 Reporter: read-only pipeline gauge (t-2823, epic t-2820)
#
# One beat = one digest: unmerged branches + merge-readiness, stale merged
# branches, inbox queue (names only — never contents), backlog signals.
#
# READ-ONLY CONTRACT (AC t-2823): zero mutations of observed pipeline state —
# no git ref/worktree changes, no object-store writes, no backlog writes, no
# inbox reads-of-content. The only writes are the digest artifact itself
# (latest.md + history.jsonl) under BRANA_DIGEST_DIR, outside the observed
# repo. The `git merge-tree --write-tree` conflict probe would normally write
# tree objects into the repo — those are redirected to a scratch object dir
# (GIT_OBJECT_DIRECTORY) that is deleted on exit, so the observed object store
# stays byte-identical (challenger finding 1, 2026-08-13).
#
# Usage: pipeline-digest.sh [repo-path]
#   BRANA_DIGEST_DIR  output dir (default ~/.claude/run-state/pipeline-digest)
#   BRANA_DIGEST_BASE integration base branch (default dev)
#   BRANA_BEATS_FILE  beat-record log used to batch one parallel beat's close-outs
#                     (default ~/.claude/scheduler/beats.jsonl — t-3275, ADR-090 §4)

set -uo pipefail

REPO="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
BASE="${BRANA_DIGEST_BASE:-dev}"
OUT_DIR="${BRANA_DIGEST_DIR:-$HOME/.claude/run-state/pipeline-digest}"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "$OUT_DIR"

g() { git -C "$REPO" "$@"; }

if ! g rev-parse --verify -q "$BASE" >/dev/null; then
    echo "pipeline-digest: base branch '$BASE' not found in $REPO" >&2
    exit 1
fi

# Scratch object dir for the merge-tree conflict probe: new objects land here
# (deleted on exit); existing objects are read via the alternates mechanism.
OBJ_SCRATCH="$(mktemp -d)"
BRANCH_ROWS="$(mktemp)"
trap 'rm -rf "$OBJ_SCRATCH" "$BRANCH_ROWS"' EXIT
REPO_OBJECTS="$(g rev-parse --path-format=absolute --git-common-dir)/objects"
merge_probe() {  # merge_probe <base> <branch> — exit 0 clean, non-zero conflict
    GIT_OBJECT_DIRECTORY="$OBJ_SCRATCH" \
    GIT_ALTERNATE_OBJECT_DIRECTORIES="$REPO_OBJECTS" \
        git -C "$REPO" merge-tree --write-tree "$1" "$2" >/dev/null 2>&1
}

WORKTREES="$(g worktree list --porcelain 2>/dev/null || true)"

worktree_for_branch() {
    printf '%s\n' "$WORKTREES" | awk -v b="refs/heads/$1" '
        $1=="worktree"{w=$2}
        $1=="branch" && $2==b {print w; exit}'
}

# --- Beat attribution (t-3275, ADR-090 §4) --------------------------------------
# N concurrent build-CLOSEs from one parallel beat land in this one queue. Without
# attribution they read as N unrelated review items — the conflation ADR-090 §4
# names. So a beat's branches are grouped into ONE entry that lists every task id.
#
# Source: the append-only beat log the runner's --run-beat writes (loops-library
# §Beat record schema). Only records that CARRY `pulled_task_ids` count — a record
# missing the key predates the field and says nothing about what it pulled, which is
# a different answer from a record whose array is empty.
#
# A beat with fewer than two ids is not a batch and is skipped entirely: one branch
# has nothing to be conflated with, so it keeps its pre-t-3275 row byte for byte.
BEATS_FILE="${BRANA_BEATS_FILE:-$HOME/.claude/scheduler/beats.jsonl}"
declare -a BEAT_LABEL=() BEAT_TASKS=()
declare -A BEAT_OF_ID=()
if [ -s "$BEATS_FILE" ] && command -v jq >/dev/null 2>&1; then
    # Line-at-a-time fromjson: one corrupt line is skipped, it never voids the beat.
    while IFS=$'\t' read -r b_num b_inst b_ids; do
        [ -z "$b_ids" ] && continue
        BEAT_LABEL+=("$b_num|$b_inst")
        BEAT_TASKS+=("$b_ids")
        for _id in $b_ids; do BEAT_OF_ID["$_id"]=$(( ${#BEAT_LABEL[@]} - 1 )); done
    done < <(jq -rR '
        fromjson? // empty
        | select(type == "object" and has("pulled_task_ids"))
        | select((.pulled_task_ids | type) == "array" and (.pulled_task_ids | length) >= 2)
        | [ (if (.beat | type) == "number" then (.beat | tostring) else "?" end),
            (.instance // .loop // "?"),
            (.pulled_task_ids | join(" ")) ]
        | @tsv' "$BEATS_FILE" 2>/dev/null)
fi

# beat_index_for <branch> — index into BEAT_LABEL, or "-" when no beat claims it.
# Task ids are read off the branch name as whole tokens, so `t-9001` never matches
# `st-9001` or `t-90015`.
beat_index_for() {
    local cand
    [ "${#BEAT_LABEL[@]}" -eq 0 ] && { printf '%s' -; return; }
    for cand in $(printf '%s' "$1" | grep -oE '(^|[^A-Za-z0-9])(st|t)-[0-9]+' \
                                   | sed -E 's/^[^A-Za-z0-9]+//'); do
        if [ -n "${BEAT_OF_ID[$cand]:-}" ]; then printf '%s' "${BEAT_OF_ID[$cand]}"; return; fi
    done
    printf '%s' -
}

unmerged_rows=""
stale_rows=""
n_unmerged=0
n_stale=0
: > "$BRANCH_ROWS"

while IFS= read -r br; do
    [ -z "$br" ] && continue
    case "$br" in "$BASE"|main|master) continue ;; esac
    if g merge-base --is-ancestor "$br" "$BASE" 2>/dev/null; then
        n_stale=$((n_stale+1))
        stale_rows="${stale_rows}- \`$br\` — merged into $BASE, not deleted
"
        continue
    fi
    n_unmerged=$((n_unmerged+1))
    counts="$(g rev-list --left-right --count "$BASE...$br" 2>/dev/null || echo "? ?")"
    behind="${counts%%[[:space:]]*}"; ahead="${counts##*[[:space:]]}"
    activity="$(g log -1 --format='%cr' "$br" 2>/dev/null || echo "?")"
    if merge_probe "$BASE" "$br"; then
        conflict="clean"
    else
        conflict="CONFLICTS"
    fi
    dirty=""
    wt="$(worktree_for_branch "$br")"
    if [ -n "$wt" ]; then
        if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
            dirty=" · **dirty worktree** ($wt)"
        else
            dirty=" · worktree $wt"
        fi
    fi
    printf '%s\t%s\t- `%s` — ahead %s / behind %s vs %s · merge: %s · last activity: %s%s\n' \
        "$(beat_index_for "$br")" "$br" "$br" "$ahead" "$behind" "$BASE" "$conflict" "$activity" "$dirty" \
        >> "$BRANCH_ROWS"
done < <(g for-each-ref refs/heads --format='%(refname:short)' --sort=-committerdate)

# Assemble: an unattributed branch keeps exactly its pre-t-3275 row, in place. A beat is
# emitted once, at the position of its first branch, with its members nested beneath it.
declare -A BEAT_EMITTED=()
while IFS=$'\t' read -r bidx br row; do
    [ -z "$br" ] && continue
    if [ "$bidx" = "-" ]; then
        unmerged_rows="${unmerged_rows}${row}
"
        continue
    fi
    [ -n "${BEAT_EMITTED[$bidx]:-}" ] && continue
    BEAT_EMITTED["$bidx"]=1
    b_num="${BEAT_LABEL[$bidx]%%|*}"; b_inst="${BEAT_LABEL[$bidx]#*|}"
    b_ids="${BEAT_TASKS[$bidx]}"
    b_n=0; for _id in $b_ids; do b_n=$((b_n+1)); done
    unmerged_rows="${unmerged_rows}- **beat $b_num** (\`$b_inst\`) — one parallel beat, $b_n tasks: $(printf '%s' "$b_ids" | sed 's/ /, /g')
"
    # members in branch order; a claimed task with no branch yet simply has no row
    while IFS=$'\t' read -r m_idx m_br m_row; do
        [ "$m_idx" = "$bidx" ] && unmerged_rows="${unmerged_rows}  ${m_row}
"
    done < "$BRANCH_ROWS"
done < "$BRANCH_ROWS"

# --- Inbox: names only, never contents ---
inbox_rows=""
n_inbox=0
if [ -d "$REPO/inbox" ]; then
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        n_inbox=$((n_inbox+1))
        inbox_rows="${inbox_rows}- $name
"
    done < <(ls -1 "$REPO/inbox" 2>/dev/null)
fi

# --- Backlog signals (degrade gracefully without brana CLI) ---
# MVP approximation (challenger finding 3): P0/P1 *pending* counts + an
# unfiltered stale excerpt stand in for "stale P0/P1"; "ready-to-drain"
# (waves, ac_state:approved — ADR-079) is absent pending CLI query support.
backlog_section=""
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }
if command -v brana >/dev/null 2>&1; then
    pending="$(timeout 30 brana backlog query --status pending --count 2>/dev/null || echo "?")"
    inprog="$(timeout 30 brana backlog query --status in_progress --count 2>/dev/null || echo "?")"
    p0="$(timeout 30 brana backlog query --status pending --priority P0 --count 2>/dev/null || echo "?")"
    p1="$(timeout 30 brana backlog query --status pending --priority P1 --count 2>/dev/null || echo "?")"
    stale_tasks="$(timeout 30 brana backlog stale 2>/dev/null | strip_ansi | head -12 || true)"
    backlog_section="pending: $pending (P0: $p0 · P1: $p1) · in_progress: $inprog

Stale tasks (excerpt):
\`\`\`
${stale_tasks:-none}
\`\`\`"
else
    backlog_section="_brana CLI unavailable — backlog signals skipped this beat_"
fi

DIGEST="# Pipeline digest — $NOW

Repo: $REPO · base: $BASE

## Unmerged branches ($n_unmerged)

${unmerged_rows:-_none — queue empty_}

## Stale merged branches ($n_stale)

${stale_rows:-_none_}

## Inbox ($n_inbox)

${inbox_rows:-_empty_}

## Backlog

$backlog_section
"

# Cheap no-op beat (challenger finding 2): if headline counts match the last
# history line, keep the durable artifacts current but print only a one-line
# status — the loop session never ingests a full digest on a quiet beat.
counts_now="\"unmerged\":$n_unmerged,\"stale_merged\":$n_stale,\"inbox\":$n_inbox"
counts_prev="$(tail -n1 "$OUT_DIR/history.jsonl" 2>/dev/null | sed 's/^{"ts":"[^"]*",//; s/}$//')"

printf '%s' "$DIGEST" > "$OUT_DIR/latest.md"
printf '{"ts":"%s",%s}\n' "$NOW" "$counts_now" >> "$OUT_DIR/history.jsonl"

if [ "$counts_now" = "$counts_prev" ]; then
    echo "no change (unmerged $n_unmerged, stale $n_stale, inbox $n_inbox) — full digest: $OUT_DIR/latest.md"
else
    printf '%s' "$DIGEST"
fi
