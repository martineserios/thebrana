#!/usr/bin/env bash
# Tests for bash-risk-classifier.sh hook (t-1889)
#
# Key invariants:
#   T3 (critical): rm -rf / rm -rf ~/ rm -rf /* rm -rf ~/  → MUST trigger T3
#   T2 (risky):    rm -rf /home/user/project               → MUST NOT trigger T3 (only T2)
#   Pass:          non-Bash tools, safe commands            → MUST pass through clean

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../bash-risk-classifier.sh"
PASS=0
FAIL=0
TOTAL=0

make_input() {
    local cmd="$1"
    # jq-encode the command to handle special chars
    local escaped
    escaped=$(printf '%s' "$cmd" | jq -Rs '.')
    printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$escaped"
}

assert_pass() {
    local desc="$1" input="$2"
    TOTAL=$((TOTAL + 1))
    local out
    out=$(echo "$input" | bash "$HOOK" 2>/dev/null)
    if echo "$out" | grep -q '"continue": true\|"continue":true' && \
       ! echo "$out" | grep -q 'additionalContext'; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    output: $out"
        FAIL=$((FAIL + 1))
    fi
}

assert_tier() {
    local desc="$1" input="$2" expected_tier="$3"
    TOTAL=$((TOTAL + 1))
    local out
    out=$(echo "$input" | bash "$HOOK" 2>/dev/null)
    if echo "$out" | grep -q "T${expected_tier}"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected T${expected_tier})"
        echo "    output: $out"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_tier() {
    local desc="$1" input="$2" excluded_tier="$3"
    TOTAL=$((TOTAL + 1))
    local out
    out=$(echo "$input" | bash "$HOOK" 2>/dev/null)
    if ! echo "$out" | grep -q "T${excluded_tier}"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (should NOT be T${excluded_tier})"
        echo "    output: $out"
        FAIL=$((FAIL + 1))
    fi
}

# ── T3: catastrophic patterns ────────────────────────────────────────

echo "bash-risk-classifier.sh tests"
echo ""
echo "── T3: catastrophic patterns (must trigger T3) ─────────────────"

assert_tier "rm -rf /" \
    "$(make_input 'rm -rf /')" 3

assert_tier "rm -rf / with trailing space" \
    "$(make_input 'rm -rf /  ')" 3

assert_tier "rm -fr /" \
    "$(make_input 'rm -fr /')" 3

assert_tier "rm -rf ~/" \
    "$(make_input 'rm -rf ~/')" 3

assert_tier "rm -rf ~" \
    "$(make_input 'rm -rf ~')" 3

assert_tier "rm -rf /*" \
    "$(make_input 'rm -rf /*')" 3

assert_tier "rm --recursive --force /" \
    "$(make_input 'rm --recursive --force /')" 3

assert_tier "dd to /dev/sda" \
    "$(make_input 'dd if=/dev/zero of=/dev/sda bs=1M')" 3

assert_tier "dd to /dev/nvme0n1" \
    "$(make_input 'dd if=/dev/zero of=/dev/nvme0n1')" 3

# ── Negative T3: project paths must NOT trigger T3 (E2026-06-08-5 regression) ──

echo ""
echo "── Negative T3: project paths must NOT trigger T3 ──────────────"

assert_not_tier "rm -rf /home/user/project — must not be T3" \
    "$(make_input 'rm -rf /home/user/project')" 3

assert_not_tier "rm -rf /tmp/spike-test — must not be T3" \
    "$(make_input 'rm -rf /tmp/spike-test')" 3

assert_not_tier "rm -rf ./build — relative path not T3" \
    "$(make_input 'rm -rf ./build')" 3

assert_not_tier "rm -rf \$WORKTREE — variable not T3" \
    "$(make_input 'rm -rf $WORKTREE')" 3

# ── T2: risky-but-recoverable ────────────────────────────────────────

echo ""
echo "── T2: risky patterns (must trigger T2 additionalContext) ──────"

assert_tier "rm -rf /home/user/project → T2" \
    "$(make_input 'rm -rf /home/user/project')" 2

assert_tier "git push --force → T2" \
    "$(make_input 'git push --force origin feature-branch')" 2

assert_tier "sudo rm → T2" \
    "$(make_input 'sudo rm /etc/config')" 2

assert_tier "rm -rf \$DIR → T2" \
    "$(make_input 'rm -rf $DIR')" 2

# ── Pass-through: safe commands ──────────────────────────────────────

echo ""
echo "── Pass-through: safe commands ─────────────────────────────────"

assert_pass "ls command" \
    "$(make_input 'ls -la /tmp')"

assert_pass "git status" \
    "$(make_input 'git status --porcelain')"

assert_pass "cargo build" \
    "$(make_input 'cargo build --release')"

assert_pass "non-Bash tool" \
    '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}'

assert_pass "empty command" \
    '{"tool_name":"Bash","tool_input":{"command":""}}'

# ── Summary ──────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
