#!/usr/bin/env bash
# Tests: post-tasks-validate.sh (and the `brana backlog rollup --file` call it
# makes) must resolve tasks.json the same way find_tasks_file() does — via
# `git rev-parse --git-common-dir` — instead of trusting the raw path
# Write/Edit reports. (t-3284, ADR-091 decision 4)
#
# Root cause reproduced here (verified in brana-cli/src/commands/backlog.rs
# cmd_rollup: `let tf = match file { Some(f) => f, None => find_tasks_file()... }`
# — when --file is given, common-dir resolution is bypassed entirely and the
# raw path is trusted, even though the resolved rollup+lock still happens
# against whatever path was handed in).
#
# Fixture: a real git repo with a linked worktree, a canonical tasks.json in
# the main checkout that HAS a rollup-eligible parent (all children done,
# parent not yet completed), and a stale, git-tracked, DIFFERENT tasks.json
# copy sitting in the worktree (the live-reproduced divergence from ADR-091's
# Context section). We invoke `brana backlog rollup --file <worktree's local
# path>` — exactly what post-tasks-validate.sh does when FILE_PATH is derived
# from a Write/Edit inside a worktree — and assert the CANONICAL (main
# checkout) file is what gets rolled up, not the stale worktree copy.
#
# Expected to FAIL today: --file bypasses find_tasks_file(), so the rollup
# lands on the worktree's stale copy and the canonical file is untouched.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# target/ is gitignored build output, not shared across worktrees — resolve
# the main checkout (git-common-dir's parent) the same way find_tasks_file()
# does, so this test runs from any worktree without its own cargo build.
COMMON_DIR=$(git -C "$REPO_ROOT" rev-parse --git-common-dir 2>/dev/null) || COMMON_DIR=""
MAIN_CHECKOUT="$REPO_ROOT"
[ -n "$COMMON_DIR" ] && MAIN_CHECKOUT="$(cd "$(dirname "$COMMON_DIR")" && pwd)"
BRANA="$MAIN_CHECKOUT/system/cli/rust/target/release/brana"
[ -x "$BRANA" ] || BRANA="$REPO_ROOT/system/cli/rust/target/release/brana"

PASS=0; FAIL=0; TOTAL=0
check() {
    local desc="$1" ok="$2" detail="${3:-}"
    TOTAL=$((TOTAL + 1))
    if [ "$ok" = "0" ]; then
        PASS=$((PASS + 1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL: $desc${detail:+ — $detail}"
    fi
}

if [ ! -x "$BRANA" ]; then
    echo "SKIP: brana binary not built at $BRANA — run 'cargo build --release' first"
    exit 0
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

MAIN="$TMPDIR/main"
mkdir -p "$MAIN/.claude"
git -C "$MAIN" init -q -b dev 2>/dev/null || (mkdir -p "$MAIN" && git -C "$MAIN" init -q && git -C "$MAIN" checkout -q -b dev)
git -C "$MAIN" config user.email test@test.com
git -C "$MAIN" config user.name test

# Canonical tasks.json: phase ph-1's only child (t-1) is completed, ph-1 itself
# is still pending — a rollup candidate.
cat > "$MAIN/.claude/tasks.json" <<'JSON'
{"version":"1","project":"fixture","tasks":[
  {"id":"ph-1","subject":"Phase","status":"pending","type":"phase"},
  {"id":"t-1","subject":"Child","status":"completed","type":"task","parent":"ph-1"}
]}
JSON
git -C "$MAIN" add -A
git -C "$MAIN" commit -q -m "fixture: canonical tasks.json with rollup candidate"

WT="$TMPDIR/wt"
git -C "$MAIN" worktree add -q -b feature "$WT" >/dev/null 2>&1

# Stale worktree-local copy — a stale checkout of the SAME rollup-eligible
# content the main checkout has (git-tracked at branch-cut time, exactly the
# live divergence ADR-091 found reproduced in this repo's own
# thebrana-t-3280 worktree). Identical content is deliberate: the defect
# under test is "which physical file does the write land on", not "does
# stale content change the rollup outcome".
cp "$MAIN/.claude/tasks.json" "$WT/.claude/tasks.json"

echo "post-tasks-validate.sh canonical-resolution tests"
echo "===================================================="
echo ""

echo "--- rollup --file <worktree-local path> should still land on the canonical file ---"
"$BRANA" backlog rollup --file "$WT/.claude/tasks.json" >/dev/null 2>&1

CANONICAL_PH1_STATUS=$(jq -r '.tasks[] | select(.id=="ph-1") | .status' "$MAIN/.claude/tasks.json")
check "canonical ph-1 rolled up to completed" \
    "$([ "$CANONICAL_PH1_STATUS" = "completed" ] && echo 0 || echo 1)" \
    "canonical ph-1 status is '$CANONICAL_PH1_STATUS', expected 'completed'"

WORKTREE_PH1_STATUS=$(jq -r '.tasks[] | select(.id=="ph-1") | .status' "$WT/.claude/tasks.json")
check "stale worktree copy is left untouched (still pending)" \
    "$([ "$WORKTREE_PH1_STATUS" = "pending" ] && echo 0 || echo 1)" \
    "worktree-local ph-1 status is '$WORKTREE_PH1_STATUS', expected untouched 'pending' — if this reads 'completed' instead, --file wrote to the stale worktree copy instead of resolving to the canonical common-dir file"

echo ""
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
