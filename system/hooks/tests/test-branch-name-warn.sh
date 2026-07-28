#!/usr/bin/env bash
# Tests for branch-name-warn.sh hook
# Pass-through cases return continue:true. Non-conforming branches are hard-blocked
# via permissionDecision:deny (E2026-06-04-5 — upgraded from continue:false in t-1848).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../branch-name-warn.sh"
PASS=0
FAIL=0
TOTAL=0

# ── Helpers ──────────────────────────────────────────────

make_input() {
    local cmd="$1"
    printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"/tmp"}' "$cmd"
}

assert_pass_no_warn() {
    local desc="$1" input="$2"
    TOTAL=$((TOTAL + 1))
    local out stderr_out
    stderr_out=$(echo "$input" | BRANA_HOOK_PROFILE=standard bash "$HOOK" 2>&1 >/dev/null) || true
    out=$(echo "$input" | BRANA_HOOK_PROFILE=standard bash "$HOOK" 2>/dev/null)
    if echo "$out" | grep -q '"continue": true\|"continue":true' && [ -z "$stderr_out" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    output:  $out"
        echo "    stderr:  $stderr_out"
        FAIL=$((FAIL + 1))
    fi
}

assert_block() {
    local desc="$1" input="$2"
    TOTAL=$((TOTAL + 1))
    local out
    out=$(echo "$input" | BRANA_HOOK_PROFILE=standard bash "$HOOK" 2>/dev/null)
    if [[ "$out" == *"permissionDecision"* && "$out" == *"deny"* && "$out" == *"convention"* ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    output:  $out"
        FAIL=$((FAIL + 1))
    fi
}

# ── Tests ────────────────────────────────────────────────

echo "branch-name-warn.sh tests"
echo ""
echo "── Pass-through (valid / special branches) ─────────────────"

assert_pass_no_warn "valid convention — switch -c" \
    "$(make_input 'git switch -c session/fix/t-1700-epic-scoped-assertion')"

assert_pass_no_warn "valid convention — checkout -b" \
    "$(make_input 'git checkout -b harness/chore/t-1717-context-budget')"

assert_pass_no_warn "valid convention — feat" \
    "$(make_input 'git switch -c backlog-git/feat/t-1619-branch-convention-docs')"

assert_pass_no_warn "main — skip" \
    "$(make_input 'git switch -c main')"

assert_pass_no_warn "docs/* — skip" \
    "$(make_input 'git switch -c docs/architecture-overview')"

assert_pass_no_warn "hotfix/* — skip" \
    "$(make_input 'git switch -c hotfix/urgent-patch')"

assert_pass_no_warn "non-branch git command — skip" \
    "$(make_input 'git commit -m \"fix: something\"')"

assert_pass_no_warn "escape hatch --force-name" \
    "$(make_input 'git switch -c my-weird-branch --force-name')"

assert_pass_no_warn "non-Bash tool — skip" \
    '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x","content":"y"},"cwd":"/tmp"}'

echo ""
echo "── Block (non-conforming branches) ─────────────────────────"

assert_block "bare feat/* (old style) warns" \
    "$(make_input 'git switch -c feat/t-1620-branch-hook')"

assert_block "no task ID warns" \
    "$(make_input 'git switch -c session/fix/branch-no-task')"

assert_block "no work-type warns" \
    "$(make_input 'git switch -c session/t-1620-branch-hook')"

assert_block "simple name warns" \
    "$(make_input 'git checkout -b my-feature')"

assert_block "git branch creation warns" \
    "$(make_input 'git branch wip-stuff')"

echo ""
echo "── t-2542: prefixes the resolver can emit must be accepted ──"

# t-2494 built resolve_branch_prefix() as the single authority for the work-type
# segment, and cross-checked its output against CLAUDE.md — but never against
# THIS hook's regex. So `design` shipped as an emittable prefix the guard rejects,
# and the existing suite stayed green. Extract the shipped function (same
# marker-sourcing idiom as tests/procedures/test-branch-prefix.sh, t-1978 rot
# class) and assert every prefix it can produce survives the guard.
PREFIX_MD="$SCRIPT_DIR/../../skills/_shared/branch-prefix.md"
PREFIX_TMP=$(mktemp -d)
trap 'rm -rf "$PREFIX_TMP"' EXIT
sed -n '/<!-- BRANCH-PREFIX-BLOCK -->/,/<!-- \/BRANCH-PREFIX-BLOCK -->/p' "$PREFIX_MD" \
    | sed '1d;$d' \
    | sed '/^```/d' > "$PREFIX_TMP/prefix.sh"

if ! grep -q 'resolve_branch_prefix()' "$PREFIX_TMP/prefix.sh"; then
    echo "  FAIL: could not extract resolve_branch_prefix() from $PREFIX_MD"
    FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1))
else
    source "$PREFIX_TMP/prefix.sh"
    # Every `kind` the resolver switches on, plus the degrade-to-feat default.
    for kind in feature fix refactor research docs design test ops ""; do
        prefix=$(resolve_branch_prefix "$kind" "")
        assert_pass_no_warn "resolver prefix '$prefix' (kind=${kind:-<empty>}) is accepted" \
            "$(make_input "git switch -c an-epic/$prefix/t-2542-cross-check")"
    done
fi

echo ""
echo "── t-2542: the mandated creation path is validated ──────────"

# git-discipline.md makes `git worktree add -b` the HARD RULE for new branches
# and forbids checkout -b. The guard checked only the forbidden paths, so every
# worktree cut passed unvalidated.
assert_pass_no_warn "worktree add -b — conforming" \
    "$(make_input 'git worktree add ../repo-x -b session/fix/t-1700-epic-scoped-assertion')"

assert_block "worktree add -b — non-conforming" \
    "$(make_input 'git worktree add ../repo-x -b my-weird-branch')"

assert_block "worktree add -b — bare prefix, no epic segment" \
    "$(make_input 'git worktree add ../repo-x -b feat/t-1620-branch-hook')"

echo ""
echo "── t-2542: quoted text is not parsed as a branch name ───────"

# Reproduced on the t-2539 commit: quoting a malformed branch inside a commit
# message got the commit blocked while the real branch was valid. Documenting
# branch drift must not be hardest in the commits that fix it.
assert_pass_no_warn "commit message quoting a bad branch is not blocked" \
    "$(make_input 'git commit -m \"docs: replace git checkout -b feat/t-123-slug with the full format\"')"

assert_pass_no_warn "commit message quoting worktree add -b is not blocked" \
    "$(make_input 'git commit -m \"docs: use git worktree add -b bad-name instead\"')"

# The guard must still catch a real creation that merely also carries a message.
assert_block "real bad branch still blocked when command also has a quoted string" \
    "$(make_input 'git switch -c my-weird-branch && git commit -m \"wip: start\"')"

echo ""
echo "── t-2542: block message names the remedy ───────────────────"

# t-2540 ruled the epic segment MANDATORY with no fallback slug: an epic-less
# task must be assigned an epic before branching. The message restated the
# grammar without naming that action.
TOTAL=$((TOTAL + 1))
msg_out=$(echo "$(make_input 'git switch -c feat/t-1620-branch-hook')" \
    | BRANA_HOOK_PROFILE=standard bash "$HOOK" 2>/dev/null)
# Must name the ACTION, not merely contain the token "{epic-slug}" from the
# grammar it already printed — otherwise the assertion passes on the very
# restatement t-2540 found unhelpful.
if echo "$msg_out" | grep -qi 'assign an epic'; then
    echo "  PASS: block message mentions assigning an epic"
    PASS=$((PASS + 1))
else
    echo "  FAIL: block message mentions assigning an epic"
    echo "    output:  $msg_out"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "── Summary ─────────────────────────────────────────────────"
echo "  ${PASS}/${TOTAL} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
