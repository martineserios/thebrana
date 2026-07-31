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
prev_arg=""

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
# stub brana — understands: backlog get <id> [--field <f>]
#
# Faithful to the real contract probed 2026-07-29:
#   known task, --field set     -> "value"          exit 0
#   known task, --field null    -> null             exit 0
#   known task, --field bogus   -> null             exit 0  <-- indistinguishable from above
#   unknown task                -> stderr message,  exit 1
#   no --field                  -> full JSON object exit 0
# The bogus-field case is why the schema self-test exists; the exit-1 case is
# what must never collapse into "no divergence". Both are reproduced here on
# purpose — a stub that got either wrong would let a broken check pass.
set -uo pipefail
prev_arg=""
[ "${1:-}" = "backlog" ] || { echo "stub: unsupported: $*" >&2; exit 2; }
# `backlog query --status X --output json` — the informational section reads this.
# Absent from the first version of this stub, which is why the substring-collision
# bug in that section went untested until an external verifier found it.
if [ "${2:-}" = "query" ]; then
    want=""
    for a in "$@"; do
        [ "$prev_arg" = "--status" ] 2>/dev/null && want="$a"
        prev_arg="$a"
    done
    printf '['
    sep=""
    while IFS=$'\t' read -r qid qst _; do
        [ -z "$qid" ] && continue
        [ -n "$want" ] && [ "$qst" != "$want" ] && continue
        printf '%s{"id":"%s","status":"%s"}' "$sep" "$qid" "$qst"
        sep=","
    done < "$FIXTURE_TASKDB"
    printf ']\n'
    exit 0
fi
[ "${2:-}" = "get" ]     || { echo "stub: unsupported: $*" >&2; exit 2; }
id="${3:-}"; field=""
[ "${4:-}" = "--field" ] && field="${5:-}"
row=$(grep -E "^${id}	" "$FIXTURE_TASKDB" 2>/dev/null | head -1)
if [ -z "$row" ]; then
    echo "task $id not found" >&2
    exit 1
fi
IFS=$'\t' read -r _ st br <<<"$row"
_json() { [ "$1" = "null" ] && printf null || printf '"%s"' "$1"; }
if [ -z "$field" ]; then
    # Full object. FIXTURE_SCHEMA_OMIT lets a test drop a key to simulate the
    # field rename that the self-test exists to catch.
    out='{"id":"'"$id"'"'
    [ "${FIXTURE_SCHEMA_OMIT:-}" != "status" ] && out="$out,\"status\":$(_json "$st")"
    [ "${FIXTURE_SCHEMA_OMIT:-}" != "branch" ] && out="$out,\"branch\":$(_json "$br")"
    echo "$out}"
    exit 0
fi
case "$field" in
    status) [ "${FIXTURE_SCHEMA_OMIT:-}" = "status" ] && echo null || _json "$st" && echo ;;
    branch) [ "${FIXTURE_SCHEMA_OMIT:-}" = "branch" ] && echo null || _json "$br" && echo ;;
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
    # The +00:00 suffix is load-bearing. `date -u` emits a UTC wall-clock time,
    # but git parses a naive timestamp as LOCAL time — under UTC-3 that shifted
    # every commit 3 hours later than intended, and integer day-division then
    # truncated 39d to 38d and 15d to 14d, so a correct >14d threshold looked
    # broken. The bug was in this line, not in the check.
    when=$(date -u -d "$days days ago" +"%Y-%m-%dT%H:%M:%S+00:00" 2>/dev/null) || return 1
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
