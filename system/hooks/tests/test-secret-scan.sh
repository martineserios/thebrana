#!/usr/bin/env bash
# Tests for secret-scan.sh hook (t-2138)
#
# Verifies that staged content containing high-signal secrets (Slack, AWS,
# GitHub, Google, private keys) is blocked at commit time, that clean and
# redacted-placeholder content passes, that the PreToolUse JSON path only
# acts on `git commit` calls, and that the BRANA_SECRET_SCAN_BYPASS escape
# hatch works.
#
# Fake tokens are ASSEMBLED AT RUNTIME from fragments so this test's own
# source file never contains a contiguous matchable secret (it would
# otherwise trip the very hook it tests when committed).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../secret-scan.sh"
PASS=0
FAIL=0

# --- Runtime-assembled fake secrets (never contiguous in this file) ---
FAKE_SLACK="xox""b-0000000000-0000000000-AAAAAAAAAAAAAAAAAAAAAAAA"
FAKE_AWS="AKIA""0000000000ABCDEF"
FAKE_GH="ghp_""000000000000000000000000000000000000"
FAKE_GOOGLE="AIza""0000000000000000000000000000000000000"
REDACTED_SLACK="xox""b-REDACTED"   # placeholder form must NOT block
FAKE_PRIVKEY="-----BEGIN ""RSA PRIVATE KEY-----"   # split so this file isn't a match

# Run the hook inside a throwaway git repo with $1 staged as file content.
# Echoes the hook exit code.
run_staged() {
    local content="$1"; shift
    local tmp; tmp=$(mktemp -d)
    (
        cd "$tmp" || exit 99
        git init -q
        git config user.email t@t.t; git config user.name t
        printf '%s\n' "$content" > leak.txt
        git add leak.txt
        bash "$HOOK" --staged "$@" >/dev/null 2>&1
        echo $?
    )
    rm -rf "$tmp"
}

# Run the hook in PreToolUse mode: JSON command on stdin, secret staged in a temp repo.
run_pretooluse() {
    local cmd="$1" content="$2"
    local tmp; tmp=$(mktemp -d)
    (
        cd "$tmp" || exit 99
        git init -q
        git config user.email t@t.t; git config user.name t
        printf '%s\n' "$content" > leak.txt
        git add leak.txt
        printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd" | bash "$HOOK" >/dev/null 2>&1
        echo $?
    )
    rm -rf "$tmp"
}

# Run PreToolUse mode with a secret in a tracked file that is MODIFIED but NOT
# staged — the `git commit -a` bypass scenario (challenger CRITICAL, t-2138).
run_pretooluse_unstaged() {
    local cmd="$1" content="$2"
    local tmp; tmp=$(mktemp -d)
    (
        cd "$tmp" || exit 99
        git init -q
        git config user.email t@t.t; git config user.name t
        echo "initial" > tracked.txt
        git add tracked.txt; git commit -qm init
        printf '%s\n' "$content" > tracked.txt   # modified, NOT staged
        printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd" | bash "$HOOK" >/dev/null 2>&1
        echo $?
    )
    rm -rf "$tmp"
}

assert_exit() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc — expected exit $expected, got $actual"
        ((FAIL++))
    fi
}

echo "Secret-Scan Hook Tests"
echo "======================"

# --- Block cases (git-hook / direct mode) ---
assert_exit "Slack token in staged file is blocked"   2 "$(run_staged "token = $FAKE_SLACK")"
assert_exit "AWS access key in staged file is blocked" 2 "$(run_staged "aws = $FAKE_AWS")"
assert_exit "GitHub token in staged file is blocked"   2 "$(run_staged "gh = $FAKE_GH")"
assert_exit "Google API key in staged file is blocked" 2 "$(run_staged "g = $FAKE_GOOGLE")"
assert_exit "private key header in staged file is blocked" 2 \
    "$(run_staged "$FAKE_PRIVKEY")"

# --- Pass cases ---
assert_exit "clean staged content passes" 0 \
    "$(run_staged "const greeting = 'hello world'")"
assert_exit "redacted placeholder passes (allowlist)" 0 \
    "$(run_staged "token = $REDACTED_SLACK")"
assert_exit "no staged changes passes" 0 "$(run_staged "")"

# --- PreToolUse JSON mode ---
assert_exit "PreToolUse: non-commit command ignored even with staged secret" 0 \
    "$(run_pretooluse "ls -la" "token = $FAKE_SLACK")"
assert_exit "PreToolUse: git commit with staged secret is blocked" 2 \
    "$(run_pretooluse "git commit -m wip" "token = $FAKE_SLACK")"
assert_exit "PreToolUse: git commit with clean staged content passes" 0 \
    "$(run_pretooluse "git commit -m wip" "clean code here")"

# --- Challenger regressions (t-2138) ---
# HIGH: a real token on a line that also says "example" must still block —
# the allowlist applies to the matched token, not the whole line.
assert_exit "token on an 'example' line still blocks (line-allowlist hole)" 2 \
    "$(run_staged "# example slack call: token = $FAKE_SLACK")"
# CRITICAL: git commit -a/-am stages tracked changes only when git runs, after
# this hook fires — the hook must scan working-tree content for -a commits.
assert_exit "PreToolUse: git commit -am with UNSTAGED tracked secret is blocked" 2 \
    "$(run_pretooluse_unstaged "git commit -am wip" "token = $FAKE_SLACK")"
assert_exit "PreToolUse: git commit -am with clean unstaged change passes" 0 \
    "$(run_pretooluse_unstaged "git commit -am wip" "just clean code")"

# --- Bypass escape hatch ---
assert_exit "BRANA_SECRET_SCAN_BYPASS=1 lets a staged secret through" 0 \
    "$(BRANA_SECRET_SCAN_BYPASS=1 run_staged "token = $FAKE_SLACK")"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
