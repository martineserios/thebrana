#!/usr/bin/env bash
# runner-verb-guard.sh — PreToolUse technical enforcement of the drain-runner
# denied-verb contract (t-2827; ADR-079 §1, ADR-080 §3/§4).
#
# WHY. ADR-079 §1 claimed the loop runner's "tool manifest" denies the approve
# verbs — true only for the headless path (autonomous-runner.sh passes
# --allowedTools to claude -p). Interactive /loop runner sessions
# (docs/guide/workflows/drain-loop.md, epic-drain.md) had no mechanism: their
# denied-verbs tables are advisory prose read by the very agent they
# constrain, and a gate armed by the party it constrains is no gate
# (ADR-076 D4).
#
# ARMING. Enforced ONLY when BRANA_RUNNER=1 is in the harness environment —
# set by the HUMAN when launching a runner session (`BRANA_RUNNER=1 claude`).
# The agent cannot modify the harness process env, so it cannot disarm this.
# Unarmed (normal human) sessions pass through untouched.
#
# DENIED when armed (the drain-loop.md / epic-drain.md tables):
#   - brana backlog ac <id> approve            / MCP backlog_ac_approve
#   - brana backlog wave approve ...           / MCP backlog_wave_approve
#     (MCP preview — no confirm_ids — stays allowed)
#   - brana backlog wave set <id> status shipped / gate / selector
#                                              / MCP backlog_wave_set (same fields)
#   - git merge ... / git push ...             (ADR-060: executors return
#     branches; a human integrates and ships)
#
# Stays PROCEDURAL (not mechanically distinguishable, documented in the
# tables): `backlog set <id> status completed` outside build CLOSE; inline
# self-review in place of a spawned challenger.
#
# THREAT MODEL BOUNDARY. This guard targets an honest-but-drifting runner —
# regex matching on the literal command string is evadable by deliberate
# shell indirection (var expansion, eval, alias shadowing), and tools outside
# the matcher (e.g. raw Write to tasks.json) bypass it entirely. It is a
# guardrail, not a hardened security boundary; the adversarial/unattended
# case is gated separately by the ADR-062 executor sandbox.
#
# Tests: system/hooks/tests/test-runner-verb-guard.sh

# Ensure valid CWD
cd /tmp 2>/dev/null || true

# Not armed → zero-cost pass-through. No profile gate: a trust-boundary hook
# must not be disable-able by profile tuning; unarmed it costs nothing anyway.
if [ "${BRANA_RUNNER:-}" != "1" ]; then
    echo '{"continue": true}'
    exit 0
fi

INPUT=$(cat)

pass_through() {
    echo '{"continue": true}'
    exit 0
}

deny() {
    local reason="$1"
    cat <<DENY_JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Runner verb guard (BRANA_RUNNER session): $reason"
  }
}
DENY_JSON
    exit 0
}

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || pass_through

case "$TOOL_NAME" in
    mcp__brana__backlog_ac_approve)
        deny "AC approval is the human trust boundary (ADR-079 §1; ADR-076 D4) — approve in an interactive human session, never in the runner."
        ;;
    mcp__brana__backlog_wave_approve)
        # Preview (no confirm_ids) is allowed; supplying confirm_ids is the
        # batched approval gesture and stays human-only (ADR-080 §4).
        N=$(echo "$INPUT" | jq -r '.tool_input.confirm_ids | length' 2>/dev/null) || pass_through
        if [ -n "$N" ] && [ "$N" != "null" ] && [ "$N" -gt 0 ] 2>/dev/null; then
            deny "wave approve with confirm_ids is batched AC approval — human-only (ADR-080 §4). Preview (no confirm_ids) is allowed."
        fi
        pass_through
        ;;
    mcp__brana__backlog_wave_set)
        FIELD=$(echo "$INPUT" | jq -r '.tool_input.field // empty' 2>/dev/null) || pass_through
        VALUE=$(echo "$INPUT" | jq -r '.tool_input.value // empty' 2>/dev/null) || pass_through
        case "$FIELD" in
            gate|selector)
                deny "the runner must never rewrite its own dependency graph (wave $FIELD) — ADR-080 §3."
                ;;
            status)
                [ "$VALUE" = "shipped" ] && deny "no auto-ship: one human ship decision per wave (ADR-080 §3.6). Empty pull ≠ done."
                ;;
        esac
        pass_through
        ;;
    Bash) ;;  # fall through to command inspection below
    *) pass_through ;;
esac

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || pass_through
[ -z "$COMMAND" ] && pass_through

if grep -qE 'backlog[[:space:]]+ac[[:space:]]+[^[:space:]]+[[:space:]]+approve' <<<"$COMMAND"; then
    deny "AC approval is the human trust boundary (ADR-079 §1; ADR-076 D4) — approve in an interactive human session, never in the runner."
fi
if grep -qE 'backlog[[:space:]]+wave[[:space:]]+approve' <<<"$COMMAND"; then
    deny "wave approve is batched AC approval — human-only (ADR-080 §4)."
fi
if grep -qE 'backlog[[:space:]]+wave[[:space:]]+set[[:space:]]+[^[:space:]]+[[:space:]]+(gate|selector)([[:space:]]|$)' <<<"$COMMAND"; then
    deny "the runner must never rewrite its own dependency graph (wave gate/selector) — ADR-080 §3."
fi
if grep -qE 'backlog[[:space:]]+wave[[:space:]]+set[[:space:]]+[^[:space:]]+[[:space:]]+status[[:space:]]+["'"'"']?shipped' <<<"$COMMAND"; then
    deny "no auto-ship: one human ship decision per wave (ADR-080 §3.6). Empty pull ≠ done."
fi
# git merge / git push — executors return branches; a human integrates and
# ships (ADR-060). Word-anchored on `git` so prose/paths don't false-match.
if grep -qE '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(merge|push)([[:space:]]|$)' <<<"$COMMAND"; then
    deny "the runner never integrates or publishes — present the command and wait for the human valve (ADR-060; drain-loop.md §The loop prompt)."
fi

pass_through
