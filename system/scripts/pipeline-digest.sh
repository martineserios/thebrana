#!/usr/bin/env bash
# pipeline-digest.sh — L0 Reporter: read-only pipeline gauge (t-2823, epic t-2820)
#
# One beat = one digest: unmerged branches + merge-readiness, stale merged
# branches, inbox queue (names only — never contents), backlog signals.
#
# READ-ONLY CONTRACT (AC t-2823): zero mutations of observed pipeline state —
# no git ref/worktree changes, no backlog writes, no inbox reads-of-content.
# The only writes are the digest artifact itself (latest.md + history.jsonl)
# under BRANA_DIGEST_DIR, outside the observed repo. `git merge-tree
# --write-tree` creates unreferenced loose objects (pruned by auto-gc); it
# moves no refs and touches no worktree.
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
    if g merge-tree --write-tree "$BASE" "$br" >/dev/null 2>&1; then
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
backlog_section=""
if command -v brana >/dev/null 2>&1; then
    pending="$(timeout 30 brana backlog query --status pending --count 2>/dev/null || echo "?")"
    inprog="$(timeout 30 brana backlog query --status in_progress --count 2>/dev/null || echo "?")"
    stale_tasks="$(timeout 30 brana backlog stale 2>/dev/null | head -12 || true)"
    backlog_section="pending: $pending · in_progress: $inprog

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

printf '%s' "$DIGEST" > "$OUT_DIR/latest.md"
printf '{"ts":"%s","unmerged":%s,"stale_merged":%s,"inbox":%s}\n' \
    "$NOW" "$n_unmerged" "$n_stale" "$n_inbox" >> "$OUT_DIR/history.jsonl"
printf '%s' "$DIGEST"
