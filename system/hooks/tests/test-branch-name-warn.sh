#!/usr/bin/env bash
# Tests for branch-name-warn.sh hook
# All cases return continue:true (advisory only). Checks that non-conforming
# branches emit a warning to stderr.

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

assert_warn() {
    local desc="$1" input="$2"
    TOTAL=$((TOTAL + 1))
    local out stderr_out
    stderr_out=$(echo "$input" | BRANA_HOOK_PROFILE=standard bash "$HOOK" 2>&1 >/dev/null) || true
    out=$(echo "$input" | BRANA_HOOK_PROFILE=standard bash "$HOOK" 2>/dev/null)
    if echo "$out" | grep -q '"continue": true\|"continue":true' && echo "$stderr_out" | grep -q "convention"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    output:  $out"
        echo "    stderr:  $stderr_out"
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
echo "── Warn (non-conforming branches) ──────────────────────────"

assert_warn "bare feat/* (old style) warns" \
    "$(make_input 'git switch -c feat/t-1620-branch-hook')"

assert_warn "no task ID warns" \
    "$(make_input 'git switch -c session/fix/branch-no-task')"

assert_warn "no work-type warns" \
    "$(make_input 'git switch -c session/t-1620-branch-hook')"

assert_warn "simple name warns" \
    "$(make_input 'git checkout -b my-feature')"

assert_warn "git branch creation warns" \
    "$(make_input 'git branch wip-stuff')"

echo ""
echo "── Summary ─────────────────────────────────────────────────"
echo "  ${PASS}/${TOTAL} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
