#!/usr/bin/env bash
# brana-scheduler on a host with no systemd (t-3375, ADR-071 amendment):
#   informational commands (status, validate) -> note + exit 0
#   action commands (deploy/enable/disable/run/teardown) -> note + exit 1
#   help / unknown-command / hosts WITH systemctl -> unchanged
# Run: bash tests/scripts/test-scheduler-no-systemd.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLI="$ROOT/system/scheduler/brana-scheduler"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
has() { case "$2" in *"$1"*) return 0;; *) return 1;; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
REAL_BASH="$(command -v bash)"
mkdir -p "$T/nosys" "$T/withsys" "$T/home"
for b in dirname basename cat sed tr head tail grep mkdir env jq; do
    p="$(command -v $b 2>/dev/null)" && { ln -sf "$p" "$T/nosys/$b"; ln -sf "$p" "$T/withsys/$b"; }
done
printf '#!/bin/sh\nexit 0\n' >"$T/withsys/systemctl"; chmod +x "$T/withsys/systemctl"

# Mirror the deployed layout: <root>/scheduler/brana-scheduler sources ../hooks/lib/scheduler-backend.sh
mkdir -p "$T/deploy/scheduler" "$T/deploy/hooks/lib"
cp "$CLI" "$T/deploy/scheduler/brana-scheduler"
cp "$ROOT/system/hooks/lib/scheduler-backend.sh" "$T/deploy/hooks/lib/"
run() { # run PATHDIR args... -> "rc|stdout+stderr"
    local pd="$1"; shift
    local out rc
    out="$(HOME="$T/home" PATH="$pd" "$REAL_BASH" "$T/deploy/scheduler/brana-scheduler" "$@" 2>&1)"; rc=$?
    echo "$rc|$out"
}
echo "=== test-scheduler-no-systemd.sh ==="
for c in status validate; do
    r="$(run "$T/nosys" $c)"
    assert "no systemd: '$c' exits 0 (informational)" 0 "${r%%|*}"
    has "no scheduler backend" "$r" && assert "no systemd: '$c' prints the note" ok ok || assert "no systemd: '$c' prints the note" ok "$r"
done
for c in "deploy" "enable job1" "disable job1" "run job1" "teardown"; do
    r="$(run "$T/nosys" $c)"
    assert "no systemd: '$c' exits 1 (action cannot happen)" 1 "${r%%|*}"
    has "no scheduler backend" "$r" && assert "no systemd: '$c' prints the note" ok ok || assert "no systemd: '$c' prints the note" ok "$r"
done
r="$(run "$T/nosys" help)"
assert "no systemd: help exits 0" 0 "${r%%|*}"
has "no scheduler backend" "$r" && assert "no systemd: help does not print the note" ok "note-shown" || assert "no systemd: help does not print the note" ok ok
r="$(run "$T/nosys" frobnicate)"
assert "no systemd: unknown command still fails" 1 "${r%%|*}"
has "Unknown command" "$r" && assert "no systemd: unknown command keeps its own message" ok ok || assert "no systemd: unknown command keeps its own message" ok "$r"
# hosts WITH systemctl: the note must never appear and the original code path runs (no config -> its own error)
for c in status "run job1" deploy; do
    r="$(run "$T/withsys" $c)"
    has "no scheduler backend" "$r" && assert "with systemctl: '$c' does not print the note" ok "note-shown" || assert "with systemctl: '$c' does not print the note" ok ok
done

# ── end to end: the Rust `brana ops` prints the SAME sentence as the shell helper ─────────────
# (they are two implementations of one message; this is what stops them drifting apart)
BRANA_BIN="${BRANA_BIN:-}"
for c in "${CARGO_TARGET_DIR:-/nonexistent}/debug/brana" "$ROOT/system/cli/rust/target/debug/brana" "$ROOT/system/cli/rust/target/release/brana"; do
    [ -z "$BRANA_BIN" ] && [ -x "$c" ] && BRANA_BIN="$c"
done
if [ -x "$BRANA_BIN" ]; then
    mkdir -p "$T/home/.claude/scheduler"
    echo '{"jobs":{"job1":{"enabled":true,"schedule":"*-*-* 03:00:00","type":"command","command":"true","project":"/tmp"}}}' >"$T/home/.claude/scheduler/scheduler.json"
    SHELL_NOTE="$(BRANA_SCHEDULER_BACKEND=none PATH="$T/nosys" "$REAL_BASH" -c "source '$ROOT/system/hooks/lib/scheduler-backend.sh'; sched_backend_note")"
    OUT="$(HOME="$T/home" BRANA_SCHEDULER_BACKEND=none "$BRANA_BIN" ops run job1 2>&1)"; RC=$?
    assert "rust: ops run exits non-zero with no backend" 1 "$([ $RC -ne 0 ] && echo 1 || echo 0)"
    has "$SHELL_NOTE" "$OUT" && assert "rust: ops run prints the shell helper's exact sentence" ok ok || assert "rust: ops run prints the shell helper's exact sentence" ok "$OUT"
    OUT="$(HOME="$T/home" BRANA_SCHEDULER_BACKEND=none "$BRANA_BIN" ops disable job1 2>&1)"; RC=$?
    assert "rust: ops disable exits 0 (the config edit succeeded)" 0 "$RC"
    has "nothing was scheduled here" "$OUT" && assert "rust: ops disable says nothing was scheduled" ok ok || assert "rust: ops disable says nothing was scheduled" ok "$OUT"
    has "$SHELL_NOTE" "$OUT" && assert "rust: ops disable carries the shell helper's exact sentence" ok ok || assert "rust: ops disable carries the shell helper's exact sentence" ok "$OUT"
    assert "rust: ops disable still edited scheduler.json" false "$(jq -r '.jobs.job1.enabled' "$T/home/.claude/scheduler/scheduler.json")"
else
    echo "  SKIP: no built brana binary (set BRANA_BIN or CARGO_TARGET_DIR) — Rust wording cross-check not run"
fi

echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
