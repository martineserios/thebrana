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
trap 'rm -rf "$OBJ_SCRATCH"' EXIT
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

unmerged_rows=""
stale_rows=""
n_unmerged=0
n_stale=0

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
    unmerged_rows="${unmerged_rows}- \`$br\` — ahead $ahead / behind $behind vs $BASE · merge: $conflict · last activity: $activity$dirty
"
done < <(g for-each-ref refs/heads --format='%(refname:short)' --sort=-committerdate)

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
