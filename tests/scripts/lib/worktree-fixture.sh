#!/usr/bin/env bash
# Fixture harness for check-worktree-divergence.sh tests (t-2545).
#
# Builds a throwaway git repo with real `git worktree add` worktrees and a stub
# `brana` on PATH. Real git is deliberate: parsing `git worktree list --porcelain`
# is a large part of what is under test, and faking it would test the fake.
# `brana` is stubbed because the real backlog is mutable global state — a test
# must not depend on, or perturb, the actual tasks.json.
#
# Usage:
#   source tests/scripts/lib/worktree-fixture.sh
#   fixture_init
#   fixture_task t-100 completed null          # id status branch-field
#   fixture_worktree wt-a harness/feat/t-100-x # dir branch  [days-ago]
#   ... run the script under test against "$FIXTURE_REPO" ...
#   fixture_cleanup

set -uo pipefail

FIXTURE_ROOT=""
FIXTURE_REPO=""
FIXTURE_TASKDB=""

fixture_init() {
    FIXTURE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/t2545-fixture.XXXXXX") || return 1
    FIXTURE_REPO="$FIXTURE_ROOT/repo"
    FIXTURE_TASKDB="$FIXTURE_ROOT/tasks.tsv"
    : > "$FIXTURE_TASKDB"

    mkdir -p "$FIXTURE_REPO"
    git -C "$FIXTURE_REPO" init -q -b dev
    git -C "$FIXTURE_REPO" config user.email t2545@example.invalid
    git -C "$FIXTURE_REPO" config user.name "t2545 fixture"
    echo seed > "$FIXTURE_REPO/README.md"
    git -C "$FIXTURE_REPO" add README.md
    git -C "$FIXTURE_REPO" commit -q -m "seed"

    # Stub brana. Mirrors the real contract probed on 2026-07-29:
    #   known task, set field   -> prints "value"   exit 0
    #   known task, null field  -> prints null      exit 0
    #   unknown task            -> stderr message,  exit 1
    # The exit-1 case is the one the check must never collapse into "no
    # divergence", so the stub has to reproduce it faithfully.
    mkdir -p "$FIXTURE_ROOT/bin"
    cat > "$FIXTURE_ROOT/bin/brana" <<'STUB'
#!/usr/bin/env bash
# stub brana — understands only: backlog get <id> --field <f>
set -uo pipefail
[ "${1:-}" = "backlog" ] || { echo "stub: unsupported: $*" >&2; exit 2; }
[ "${2:-}" = "get" ]     || { echo "stub: unsupported: $*" >&2; exit 2; }
id="${3:-}"; field=""
[ "${4:-}" = "--field" ] && field="${5:-}"
row=$(grep -E "^${id}	" "$FIXTURE_TASKDB" 2>/dev/null | head -1)
if [ -z "$row" ]; then
    echo "task $id not found" >&2
    exit 1
fi
IFS=$'\t' read -r _ st br <<<"$row"
case "$field" in
    status) [ "$st" = "null" ] && echo null || echo "\"$st\"" ;;
    branch) [ "$br" = "null" ] && echo null || echo "\"$br\"" ;;
    *)      echo null ;;
esac
exit 0
STUB
    chmod +x "$FIXTURE_ROOT/bin/brana"
    export FIXTURE_TASKDB
    export PATH="$FIXTURE_ROOT/bin:$PATH"
}

# fixture_task <id> <status> <branch-field>   ("null" for an unset field)
# Omit entirely to simulate a task id that is absent from the backlog.
fixture_task() {
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$FIXTURE_TASKDB"
}

# fixture_worktree <dirname> <branch> [days-ago]
# days-ago backdates the worktree's HEAD commit so idle age is controllable
# without waiting. Uses committer date, which is what `git log --format=%ct` reads.
fixture_worktree() {
    local dir="$1" branch="$2" days="${3:-0}" path when
    path="$FIXTURE_ROOT/$dir"
    git -C "$FIXTURE_REPO" worktree add -q -b "$branch" "$path" 2>/dev/null || return 1
    echo "$dir" > "$path/work.txt"
    when=$(date -u -d "$days days ago" +"%Y-%m-%dT%H:%M:%S" 2>/dev/null) || return 1
    git -C "$path" add work.txt
    GIT_AUTHOR_DATE="$when" GIT_COMMITTER_DATE="$when" \
        git -C "$path" commit -q -m "work in $dir"
}

# fixture_worktree_detached <dirname> — worktree with no branch line at all.
fixture_worktree_detached() {
    local dir="$1" path head
    path="$FIXTURE_ROOT/$dir"
    head=$(git -C "$FIXTURE_REPO" rev-parse HEAD)
    git -C "$FIXTURE_REPO" worktree add -q --detach "$path" "$head" 2>/dev/null
}

fixture_cleanup() {
    [ -n "$FIXTURE_ROOT" ] && [ -d "$FIXTURE_ROOT" ] && rm -rf "$FIXTURE_ROOT"
    FIXTURE_ROOT=""; FIXTURE_REPO=""; FIXTURE_TASKDB=""
}
