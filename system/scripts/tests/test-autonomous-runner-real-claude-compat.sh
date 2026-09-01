#!/usr/bin/env bash
# test-autonomous-runner-real-claude-compat.sh — real (non-stub) claude -p dispatch through
# the actual sandbox_claude() path (t-3257, ADR-062).
#
# THE GAP THIS CLOSES. test-autonomous-runner-sandbox.sh (Check 61) proves the jail CONTAINS
# an adversary, but its `claude` is a stub — it never proves the jail can run the REAL
# subscription binary at all. That gap is exactly how the 2026-06-22 regression hid: the
# merged bwrap sandbox looked green against the stub while real `claude -p` failed to
# authenticate inside it (RO-cred-bind bug — claude rewrites ~/.claude.json on startup, so a
# read-only bind bails "Not logged in"). Every "proven with real claude" claim since (June
# bwrap fix, 08-31 docker PONG) has been a one-off manual spike, never wired into CI — so the
# regression class could recur silently. This test is the CI-gated version of that spike.
#
# WHY OPT-IN, NOT WIRED INTO validate.sh's DEFAULT SWEEP. Unlike Check 61's stub battery
# (hermetic, free, instant), this makes ONE REAL API call through a real model — it costs
# tokens, needs network + valid subscription auth, and is not appropriate to run on every
# `validate.sh` invocation (CI, pre-commit, casual local runs). Gate: RUNNER_LIVE_CLAUDE_TEST=1.
#
# CADENCE — run this explicitly:
#   - before enabling any unattended `--run-batch` use (the thing this whole guard exists for)
#   - after any change to sandbox_claude() / stage_runner_home() / the egress proxy
#   - after a Claude Code CLI upgrade (auth/config file shape can change, as it did in June)
#
# Extracts the shipped sandbox_claude() from autonomous-runner.sh (SANDBOX-CLAUDE-BLOCK
# markers) rather than reimplementing it, so this test cannot drift from the real dispatch
# path (same convention as EPIC-WALK-BLOCK / BRANCH-PREFIX-BLOCK, t-2494/t-2487).
#
# Two assertions, both required (a test that can only ever pass is not a regression guard):
#   PART A — real claude, real creds, through sandbox_claude(): rc=0 + expected output.
#   PART B — real claude, NO creds staged (simulated auth break), through sandbox_claude():
#            must FAIL LOUDLY (non-zero rc, recognizable "not logged in" signature) — proves
#            the assertion actually discriminates pass/fail rather than always reporting green
#            (the failure mode of a check that "passes" no matter what happens inside the jail).
set -u

RUNNER_SRC="$(git rev-parse --show-toplevel 2>/dev/null)/system/scripts/autonomous-runner.sh"
[ -f "$RUNNER_SRC" ] || { echo "FAIL: runner not found at $RUNNER_SRC"; exit 1; }
REAL_SCRIPT_DIR="$(dirname "$RUNNER_SRC")"

echo "autonomous-runner real-claude sandbox compat check (t-3257, ADR-062)"

if [ "${RUNNER_LIVE_CLAUDE_TEST:-0}" != "1" ]; then
  echo "  SKIP: opt-in only (real API call, real cost). Run with RUNNER_LIVE_CLAUDE_TEST=1."
  echo "  Cadence: before unattended --run-batch use, after any sandbox_claude() change,"
  echo "           after a claude CLI upgrade."
  exit 0
fi

if ! command -v bwrap >/dev/null 2>&1; then
  echo "  SKIP: bwrap not installed — sandbox untestable here (ADR-062)"
  exit 0
fi

PASS=0; FAIL=0
ok(){ if eval "$2"; then PASS=$((PASS+1)); echo "  ✓ $1"; else FAIL=$((FAIL+1)); echo "  ✗ $1"; fi; }

# ── extract the shipped sandbox_claude() (+ deps) — never a reimplementation ──────
TMPDIR_T="$(mktemp -d /tmp/runner-realclaude-src-XXXXXX)"
trap 'rm -rf "$TMPDIR_T" "${WD1:-}" "${WD2:-}" "${NOAUTH_HOME:-}"' EXIT

sed -n '/# SANDBOX-CLAUDE-BLOCK/,/# \/SANDBOX-CLAUDE-BLOCK/p' "$RUNNER_SRC" > "$TMPDIR_T/sandbox-claude.sh"
if [ ! -s "$TMPDIR_T/sandbox-claude.sh" ]; then
  echo "ERROR: SANDBOX-CLAUDE-BLOCK markers missing or empty in $RUNNER_SRC — cannot extract"
  exit 1
fi
if ! grep -q "^sandbox_claude()" "$TMPDIR_T/sandbox-claude.sh"; then
  echo "ERROR: SANDBOX-CLAUDE-BLOCK does not contain sandbox_claude() — markers moved?"
  exit 1
fi
# shellcheck disable=SC1091
source "$TMPDIR_T/sandbox-claude.sh"
# The sourced block computes RUNNER_SCRIPT_DIR from ITS OWN path (the temp extraction file) —
# override it to the real script dir so sandbox_claude() finds runner-egress-proxy.py.
RUNNER_SCRIPT_DIR="$REAL_SCRIPT_DIR"

# ── resolve the REAL binary — never a stub, and log it for transparency ───────────
CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
REAL_CLAUDE="$(resolve_claude)"
if [ -z "$REAL_CLAUDE" ] || [ ! -x "$REAL_CLAUDE" ]; then
  echo "FAIL: no real claude binary resolved (CLAUDE_BIN=$CLAUDE_BIN, PATH has none) — cannot run this check"
  exit 1
fi
case "$REAL_CLAUDE" in
  /tmp/*) echo "FAIL: resolved claude binary is under /tmp ($REAL_CLAUDE) — refusing to treat a stub as real"; exit 1 ;;
esac
echo "  using: $REAL_CLAUDE ($("$REAL_CLAUDE" --version 2>/dev/null || echo 'version unknown'))"

PROMPT='Reply with exactly the single word: PONG'
MARK="PONG"

# ── PART A: real creds, real dispatch — must succeed ───────────────────────────────
WD1="$(mktemp -d /tmp/runner-realclaude-wd-XXXXXX)"
OUT_A="$(printf '%s' "$PROMPT" | sandbox_claude "$WD1" -p --model haiku --allowedTools "" --output-format text 2>&1)"
RC_A=$?
ok "PART A: real claude in sandbox_claude() exits 0"        '[ "$RC_A" -eq 0 ]'
ok "PART A: real claude in sandbox_claude() replies $MARK"  'printf "%s" "$OUT_A" | grep -q "$MARK"'
if [ "$RC_A" -ne 0 ] || ! printf '%s' "$OUT_A" | grep -q "$MARK"; then
  echo "  --- captured output (PART A) ---"
  printf '%s\n' "$OUT_A" | sed 's/^/  | /'
  if printf '%s' "$OUT_A" | grep -qiE "not logged in|please run /login|authentication"; then
    echo "  >>> AUTH FAILURE inside the jail — this is the 2026-06-22 regression class. <<<"
  fi
fi

# ── PART B: NO creds staged (simulated auth break) — must fail LOUDLY, not silently ─
NOAUTH_HOME="$(mktemp -d /tmp/runner-realclaude-noauth-XXXXXX)"
WD2="$(mktemp -d /tmp/runner-realclaude-wd2-XXXXXX)"
OUT_B="$(HOME="$NOAUTH_HOME" bash -c "$(declare -f resolve_claude stage_runner_home sandbox_claude); CLAUDE_BIN='$REAL_CLAUDE' RUNNER_SCRIPT_DIR='$REAL_SCRIPT_DIR' SANDBOX=1 EGRESS='${EGRESS:-1}' EGRESS_ALLOW='${EGRESS_ALLOW:-api.anthropic.com}' EGRESS_PORT='${EGRESS_PORT:-18080}' RUNNER_DISPATCH_TIMEOUT=60; printf '%s' '$PROMPT' | sandbox_claude '$WD2' -p --model haiku --allowedTools '' --output-format text" 2>&1)"
RC_B=$?
ok "PART B: no-creds dispatch fails (non-zero rc)"        '[ "$RC_B" -ne 0 ]'
ok "PART B: no-creds failure names the auth problem"      'printf "%s" "$OUT_B" | grep -qiE "not logged in|please run /login|authentication"'
if [ "$RC_B" -eq 0 ]; then
  echo "  --- captured output (PART B — should have failed, did not) ---"
  printf '%s\n' "$OUT_B" | sed 's/^/  | /'
fi

echo "  passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
