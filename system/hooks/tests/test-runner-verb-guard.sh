#!/usr/bin/env bash
# Tests for runner-verb-guard.sh — technical enforcement of the drain-runner
# denied-verb contract (t-2827; ADR-079 §1, ADR-080 §3/§4).
#
# THE BUG. ADR-079 §1 claimed the loop runner's "tool manifest" denies
# `backlog ac approve` — but interactive /loop runner sessions (drain-loop.md,
# epic-drain.md) have no manifest mechanism; the denied-verbs tables were
# advisory prose read by the very agent they constrain. A gate armed by the
# party it constrains is no gate (ADR-076 D4).
#
# THE CONTROL UNDER TEST. A PreToolUse hook armed ONLY when BRANA_RUNNER=1 is
# in the harness environment — set by the HUMAN launching the runner session
# (`BRANA_RUNNER=1 claude`). The agent cannot modify the harness env. Armed,
# it denies the denied-verb list; unarmed sessions pass through untouched.
#
# Deny convention: permissionDecision "deny" JSON (main-guard.sh style).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../runner-verb-guard.sh"
PASS=0
FAIL=0

if [ ! -f "$HOOK" ]; then
    echo "ERROR: $HOOK does not exist"
    echo "Results: 0 passed, 1 failed"
    exit 1
fi

run_hook() {  # run_hook <armed:0|1> <json>
    local armed="$1" input="$2"
    if [ "$armed" = "1" ]; then
        OUT=$(echo "$input" | BRANA_RUNNER=1 bash "$HOOK" 2>/dev/null)
    else
        OUT=$(echo "$input" | BRANA_RUNNER= bash "$HOOK" 2>/dev/null)
    fi
}

assert_deny() {
    local desc="$1" armed="$2" input="$3"
    run_hook "$armed" "$input"
    if grep -q '"permissionDecision": *"deny"' <<<"$OUT"; then
        echo "  PASS: $desc"; (( PASS++ )) || true
    else
        echo "  FAIL: $desc (expected deny, got: $OUT)"; (( FAIL++ )) || true
    fi
}

assert_allow() {
    local desc="$1" armed="$2" input="$3"
    run_hook "$armed" "$input"
    if grep -q '"continue": *true' <<<"$OUT" && ! grep -q '"deny"' <<<"$OUT"; then
        echo "  PASS: $desc"; (( PASS++ )) || true
    else
        echo "  FAIL: $desc (expected pass-through, got: $OUT)"; (( FAIL++ )) || true
    fi
}

bash_input() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)"; }
mcp_input()  { printf '{"tool_name":"%s","tool_input":%s}' "$1" "$2"; }

echo "=== armed (BRANA_RUNNER=1): approve verbs denied ==="
assert_deny "CLI ac approve" 1 "$(bash_input 'brana backlog ac t-123 approve')"
assert_deny "CLI ac approve via full path" 1 "$(bash_input '/usr/local/bin/brana backlog ac t-9 approve')"
assert_deny "MCP backlog_ac_approve" 1 "$(mcp_input mcp__brana__backlog_ac_approve '{"task_id":"t-123"}')"
assert_deny "CLI wave approve" 1 "$(bash_input 'brana backlog wave approve wave-1')"
assert_deny "MCP wave_approve WITH confirm_ids" 1 "$(mcp_input mcp__brana__backlog_wave_approve '{"wave_id":"wave-1","confirm_ids":["t-1"]}')"
assert_allow "MCP wave_approve preview (no confirm_ids) stays allowed" 1 "$(mcp_input mcp__brana__backlog_wave_approve '{"wave_id":"wave-1"}')"

echo "=== armed: wave graph/ship self-edits denied (ADR-080 §3) ==="
assert_deny "CLI wave set status shipped" 1 "$(bash_input 'brana backlog wave set wave-3 status shipped')"
assert_deny "CLI wave set gate" 1 "$(bash_input 'brana backlog wave set wave-3 gate wave-2')"
assert_deny "CLI wave set selector" 1 "$(bash_input 'brana backlog wave set wave-3 selector tag:x')"
assert_deny "CLI wave ship alias (t-3022)" 1 "$(bash_input 'brana backlog wave ship wave-3')"
assert_deny "CLI wave ship via full path" 1 "$(bash_input '/usr/local/bin/brana backlog wave ship wave-3')"
assert_deny "MCP wave_set status=shipped" 1 "$(mcp_input mcp__brana__backlog_wave_set '{"wave_id":"wave-3","field":"status","value":"shipped"}')"
assert_deny "MCP wave_set gate" 1 "$(mcp_input mcp__brana__backlog_wave_set '{"wave_id":"wave-3","field":"gate","value":"wave-2"}')"
assert_deny "MCP wave_set selector" 1 "$(mcp_input mcp__brana__backlog_wave_set '{"wave_id":"wave-3","field":"selector","value":"tag:x"}')"
assert_deny "CLI wave set contract (t-3162)" 1 "$(bash_input 'brana backlog wave set wave-3 contract \"CHECK: merged to dev\"')"
assert_deny "MCP wave_set contract (t-3162)" 1 "$(mcp_input mcp__brana__backlog_wave_set '{"wave_id":"wave-3","field":"contract","value":"CHECK: merged to dev"}')"
assert_allow "MCP wave_set wip_limit stays allowed" 1 "$(mcp_input mcp__brana__backlog_wave_set '{"wave_id":"wave-3","field":"wip_limit","value":"1"}')"
assert_allow "MCP wave_set status=draining stays allowed" 1 "$(mcp_input mcp__brana__backlog_wave_set '{"wave_id":"wave-3","field":"status","value":"draining"}')"
assert_allow "CLI wave set wip_limit stays allowed" 1 "$(bash_input 'brana backlog wave set wave-3 wip_limit 1')"

echo "=== armed: integration/publish denied (ADR-060) ==="
assert_deny "git merge" 1 "$(bash_input 'git merge --no-ff feat/x -m msg')"
assert_deny "git -C merge" 1 "$(bash_input 'git -C /repo merge feat/x')"
assert_deny "git push" 1 "$(bash_input 'git push origin main dev')"

echo "=== armed: benign commands pass through ==="
assert_allow "backlog get" 1 "$(bash_input 'brana backlog get t-1')"
assert_allow "ac propose (not approve)" 1 "$(bash_input 'brana backlog ac t-1 propose')"
assert_allow "wave pull" 1 "$(bash_input 'brana backlog wave pull wave-1')"
assert_allow "wave drain" 1 "$(bash_input 'brana backlog wave drain wave-1')"
assert_allow "git commit" 1 "$(bash_input 'git commit -m "feat: x"')"
assert_allow "git status mentioning merge in a path" 1 "$(bash_input 'cat docs/merge-notes.md')"
assert_allow "Write tool untouched" 1 '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x"}}'
assert_allow "empty input" 1 '{}'

echo "=== unarmed: everything passes through ==="
assert_allow "ac approve allowed unarmed" 0 "$(bash_input 'brana backlog ac t-123 approve')"
assert_allow "MCP ac_approve allowed unarmed" 0 "$(mcp_input mcp__brana__backlog_ac_approve '{"task_id":"t-123"}')"
assert_allow "wave set shipped allowed unarmed" 0 "$(bash_input 'brana backlog wave set wave-3 status shipped')"
assert_allow "git merge allowed unarmed" 0 "$(bash_input 'git merge feat/x')"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
