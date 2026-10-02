#!/usr/bin/env bash
# Tests for system/scripts/hook-test-sweep.sh — parallel test-*.sh discovery
# and execution (t-2622).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWEEP="$SCRIPT_DIR/../hook-test-sweep.sh"
PASS=0
FAIL=0
TOTAL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

ok()   { TOTAL=$((TOTAL+1)); echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [ ! -f "$SWEEP" ]; then
    echo "FAIL: $SWEEP does not exist"
    exit 1
fi

# ── Test 1: all-green directory → exit 0, correct count ──────────────────
D1="$WORK/all-green"
mkdir -p "$D1"
printf '#!/usr/bin/env bash\nexit 0\n' > "$D1/test-a.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$D1/test-b.sh"
OUT1=$(bash "$SWEEP" "$D1" 2>&1)
RC1=$?
if [ "$RC1" -eq 0 ]; then ok "all-green directory exits 0"; else bad "all-green directory exits 0 (got $RC1)"; fi
if echo "$OUT1" | grep -q "2 suite(s), 0 failed"; then ok "all-green reports 2 suites, 0 failed"; else bad "all-green suite count — got: $OUT1"; fi

# ── Test 2: one red suite → nonzero exit, failure named ───────────────────
D2="$WORK/one-red"
mkdir -p "$D2"
printf '#!/usr/bin/env bash\nexit 0\n' > "$D2/test-a.sh"
printf '#!/usr/bin/env bash\necho "boom"; exit 1\n' > "$D2/test-b.sh"
OUT2=$(bash "$SWEEP" "$D2" 2>&1)
RC2=$?
if [ "$RC2" -ne 0 ]; then ok "one red suite exits nonzero"; else bad "one red suite should exit nonzero"; fi
if echo "$OUT2" | grep -q "FAIL: test-b.sh"; then ok "red suite named in output"; else bad "red suite not named — got: $OUT2"; fi

# ── Test 1b: every suite runs under a throwaway HOME (t-3389) ─────────────
# validate.sh Check 70 runs ~60 hook suites through this sweep; it is the operator's most frequent
# test path, so it must give the same isolation as run-test-suites.sh — otherwise a suite that
# forgets to fake HOME writes into the real ~/.claude (the Mac run found test entries in
# run-state/persist-failures.log). The scratch HOME lives INSIDE the caller's HOME (hooks pass /tmp/*
# through; fixture repos must stay out of /tmp) and is removed afterwards.
D1B="$WORK/home-iso"; CALLER_HOME="$WORK/caller-home"; mkdir -p "$D1B" "$CALLER_HOME"
cat > "$D1B/test-home.sh" <<'SUITE'
#!/usr/bin/env bash
echo "HOME=$HOME"; touch "$HOME/marker-from-suite"
d="$(mktemp -d)"; git -C "$d" init -q && : >"$d/f" && git -C "$d" add f && git -C "$d" commit -q -m x && echo committed-ok; rm -rf "$d"
SUITE
OUT1B=$(HOME="$CALLER_HOME" HOOK_TEST_SWEEP_TAIL=20 bash "$SWEEP" "$D1B" 2>&1); RC1B=$?
if [ "$RC1B" -eq 0 ]; then ok "home-iso: suite ran green under the sweep"; else bad "home-iso: suite should be green — got: $OUT1B"; fi
if [ ! -e "$CALLER_HOME/marker-from-suite" ]; then ok "home-iso: nothing landed in the caller's HOME"; else bad "home-iso: the suite wrote into the caller's HOME"; fi
LEFT=$(find "$CALLER_HOME" -maxdepth 1 -name '.brana-test-home.*' | wc -l | tr -d ' ')
if [ "$LEFT" = 0 ]; then ok "home-iso: scratch HOME removed after the suite"; else bad "home-iso: $LEFT scratch HOME(s) left behind"; fi
# the sweep only shows a suite's output on failure, so prove the HOME via a failing probe suite
printf '#!/usr/bin/env bash\necho "HOME=$HOME"; exit 1\n' > "$D1B/test-probe.sh"
OUT1C=$(HOME="$CALLER_HOME" HOOK_TEST_SWEEP_TAIL=20 bash "$SWEEP" "$D1B/test-probe.sh" 2>&1)
case "$OUT1C" in *"HOME=$CALLER_HOME/.brana-test-home."*) ok "home-iso: the suite's HOME is a scratch dir inside the caller's HOME";; *) bad "home-iso: suite HOME not a scratch dir inside the caller's HOME — got: $OUT1C";; esac
rm -f "$D1B/test-probe.sh"

# ── Test 2b: failing suite output is surfaced, and HOOK_TEST_SWEEP_TAIL bounds it ──
# (t-3023) CI's only view of a red suite is this tail; the default 5 was hiding
# the failing assertion behind the suite's own summary lines.
D2B="$WORK/tail"
mkdir -p "$D2B"
printf '#!/usr/bin/env bash\nfor i in 1 2 3 4 5 6 7 8; do echo "line$i"; done; echo "ASSERT-FAILED"; echo "summary"; exit 1\n' > "$D2B/test-t.sh"
OUT2B=$(bash "$SWEEP" "$D2B" 2>&1)
if echo "$OUT2B" | grep -q "ASSERT-FAILED"; then ok "red suite tail surfaced by default"; else bad "red suite tail missing — got: $OUT2B"; fi
OUT2C=$(HOOK_TEST_SWEEP_TAIL=1 bash "$SWEEP" "$D2B" 2>&1)
if echo "$OUT2C" | grep -q "summary" && ! echo "$OUT2C" | grep -q "ASSERT-FAILED"; then ok "HOOK_TEST_SWEEP_TAIL bounds the surfaced tail"; else bad "HOOK_TEST_SWEEP_TAIL not honoured — got: $OUT2C"; fi
OUT2D=$(HOOK_TEST_SWEEP_TAIL=40 bash "$SWEEP" "$D2B" 2>&1)
if echo "$OUT2D" | grep -q "line1"; then ok "HOOK_TEST_SWEEP_TAIL=40 shows the whole short suite"; else bad "tail=40 should show line1 — got: $OUT2D"; fi

# ── Test 3: explicit file args (not just directories) ─────────────────────
D3="$WORK/explicit"
mkdir -p "$D3"
printf '#!/usr/bin/env bash\nexit 0\n' > "$D3/test-only.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$D3/test-ignored.sh"
OUT3=$(bash "$SWEEP" "$D3/test-only.sh" 2>&1)
if echo "$OUT3" | grep -q "1 suite(s), 0 failed"; then ok "explicit file arg runs only that file"; else bad "explicit file arg — got: $OUT3"; fi

# ── Test 4: non-test-*.sh files in the directory are ignored ─────────────
D4="$WORK/mixed"
mkdir -p "$D4"
printf '#!/usr/bin/env bash\nexit 0\n' > "$D4/test-real.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$D4/helper.sh"
OUT4=$(bash "$SWEEP" "$D4" 2>&1)
RC4=$?
if [ "$RC4" -eq 0 ]; then ok "non-test-*.sh helper file ignored, sweep stays green"; else bad "helper.sh should not have been swept — got: $OUT4"; fi

# ── Test 5: no matching files → exit 0, informational ─────────────────────
D5="$WORK/empty"
mkdir -p "$D5"
OUT5=$(bash "$SWEEP" "$D5" 2>&1)
RC5=$?
if [ "$RC5" -eq 0 ]; then ok "empty directory exits 0"; else bad "empty directory should exit 0"; fi

# ── Test 6: default targets (no args) resolve relative to the repo root ──
OUT6=$(bash "$SWEEP" 2>&1)
RC6=$?
if echo "$OUT6" | grep -qE '[0-9]+ suite\(s\)'; then ok "no-arg default sweep runs the repo's real suites"; else bad "no-arg default sweep — got: $OUT6"; fi
if [ "$RC6" -eq 0 ]; then ok "default sweep (real repo suites) is green"; else bad "default sweep should be green — got: $OUT6"; fi

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed."
[ "$FAIL" -eq 0 ]
