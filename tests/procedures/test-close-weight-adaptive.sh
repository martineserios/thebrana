#!/usr/bin/env bash
# Tests for /brana:close weight-adaptive NANO/LIGHT/INSTANT/FULL classification
# (t-1655 original; updated t-1973 for Track 1 / ADR-052 §5).
#
# Since Track 1, auto-classified heavy sessions are INSTANT (snapshot + queue +
# handoff, extraction deferred to the nightly cron); FULL fires only on an
# explicit --full. NANO and LIGHT behavior is unchanged — these assertions are
# the regression net the t-1970 plan challenger required.
#
# Run: bash tests/procedures/test-close-weight-adaptive.sh

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_mode() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected $expected, got $actual)"
        FAIL=$((FAIL + 1))
    fi
}

# Single source of truth (t-1978): the test executes the REAL classification
# script — the same one the close gate calls. No replicated logic to rot.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASSIFY="$SCRIPT_DIR/../../system/scripts/close-classify.sh"
if [ ! -x "$CLASSIFY" ]; then
    echo "FAIL: $CLASSIFY missing or not executable"
    exit 1
fi

# Args: COMMIT_COUNT, CHANGED_FILES (newline-separated), ARGUMENTS.
classify() {
    local COMMIT_COUNT="${1:-1}"
    local CHANGED_FILES="$2"
    local ARGUMENTS="${3:-}"
    echo "$CHANGED_FILES" | bash "$CLASSIFY" --commit-count "$COMMIT_COUNT" --arguments "$ARGUMENTS"
}

echo "=== test-close-weight-adaptive.sh ==="
echo ""

# ── Behavioral changes → INSTANT (was FULL pre-Track-1) ──────────────────────

echo "Behavioral changes → INSTANT"
MODE=$(classify 1 "system/hooks/pre-tool-use.sh")
assert_mode ".sh file → INSTANT" "INSTANT" "$MODE"

MODE=$(classify 1 ".claude/settings.json")
assert_mode ".claude/settings.json → INSTANT" "INSTANT" "$MODE"

MODE=$(classify 1 "system/plugin.json")
assert_mode "system/*.json → INSTANT" "INSTANT" "$MODE"

MODE=$(classify 1 ".claude/tasks.json
.claude/settings.json")
assert_mode "tasks.json + settings.json → INSTANT" "INSTANT" "$MODE"

MODE=$(classify 2 "README.md")
assert_mode "2 commits + only .md → INSTANT" "INSTANT" "$MODE"

for ext in rs ts tsx js jsx py toml yaml yml; do
    MODE=$(classify 1 "src/file.$ext")
    assert_mode ".$ext → INSTANT" "INSTANT" "$MODE"
done

# ── NANO regression (unchanged by Track 1) ───────────────────────────────────

echo ""
echo "NANO regression — unchanged"
MODE=$(classify 1 ".claude/tasks.json")
assert_mode "tasks.json only, 1 commit → NANO" "NANO" "$MODE"

MODE=$(classify 1 ".claude/tasks.json
docs/some-note.md")
assert_mode "tasks.json + .md, 1 commit → NANO" "NANO" "$MODE"

MODE=$(classify 1 "docs/note.md")
assert_mode "single .md, 1 commit → NANO" "NANO" "$MODE"

# ── LIGHT regression (unchanged by Track 1) ──────────────────────────────────

echo ""
echo "LIGHT regression — unchanged"
MODE=$(classify 1 "docs/a.md
docs/b.md
docs/c.md
docs/d.md
docs/e.md
docs/f.md")
assert_mode "1 commit, 6 non-code files → LIGHT" "LIGHT" "$MODE"

MODE=$(classify 0 "docs/a.md
docs/b.md
docs/c.md
docs/d.md
docs/e.md
docs/f.md")
assert_mode "0 commits, uncommitted .md spread → LIGHT" "LIGHT" "$MODE"

# ── Escape hatches ────────────────────────────────────────────────────────────

echo ""
echo "Escape hatches"
MODE=$(classify 1 "system/hooks/pre-tool-use.sh" "--light")
assert_mode "--light overrides .sh (→ LIGHT)" "LIGHT" "$MODE"

MODE=$(classify 1 ".claude/tasks.json" "--full")
assert_mode "--full is the ONLY route to FULL" "FULL" "$MODE"

MODE=$(classify 3 "src/main.rs" "--full")
assert_mode "--full overrides INSTANT auto-class" "FULL" "$MODE"

MODE=$(classify 3 "src/main.rs" "--nano")
assert_mode "--nano overrides INSTANT auto-class" "NANO" "$MODE"

# ── No auto path reaches FULL (Track 1 invariant) ────────────────────────────

echo ""
echo "Track 1 invariant: FULL requires --full"
for args in "" "--light" "--nano"; do
    for files in "src/x.rs" ".claude/settings.json" "README.md"; do
        MODE=$(classify 5 "$files" "$args")
        TOTAL=$((TOTAL + 1))
        if [ "$MODE" != "FULL" ]; then
            echo "  PASS: commit=5 files=$files args='$args' → $MODE (not FULL)"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: commit=5 files=$files args='$args' auto-classified FULL"
            FAIL=$((FAIL + 1))
        fi
    done
done

# ── Orientation flags force weight (ADR-053 §1, t-1980) ─────────────────────
# Orientation wins over auto-classification AND over weight escape hatches.
# --patterns prints LIGHT-INLINE, a weight distinct from LIGHT: the gate's
# snapshot+queue step (Step 1b) runs for INSTANT/LIGHT/FULL only, so
# LIGHT-INLINE structurally never queues (ADR-053 §3 — the documented
# exception to ADR-052 §5). This is the queue-suppression regression.

echo ""
echo "Orientation flags (ADR-053)"
MODE=$(classify 1 "docs/note.md" "--continue")
assert_mode "--continue forces INSTANT (auto would be NANO)" "INSTANT" "$MODE"

MODE=$(classify 1 "docs/note.md" "--finish")
assert_mode "--finish forces INSTANT (auto would be NANO)" "INSTANT" "$MODE"

MODE=$(classify 5 "src/main.rs" "--patterns")
assert_mode "--patterns forces LIGHT-INLINE (auto would be INSTANT)" "LIGHT-INLINE" "$MODE"

MODE=$(classify 5 "src/main.rs" "--abort")
assert_mode "--abort forces NANO (auto would be INSTANT)" "NANO" "$MODE"

MODE=$(classify 1 "src/main.rs" "--continue")
assert_mode "--continue on code session stays INSTANT" "INSTANT" "$MODE"

echo ""
echo "Orientation precedence over weight escape hatches"
MODE=$(classify 1 "docs/note.md" "--full --patterns")
assert_mode "--patterns beats --full" "LIGHT-INLINE" "$MODE"

MODE=$(classify 1 "docs/note.md" "--continue --light")
assert_mode "--continue beats --light" "INSTANT" "$MODE"

echo ""
echo "Explicit --mode-override argument (programmatic callers)"
MODE=$(echo "docs/note.md" | bash "$CLASSIFY" --commit-count 1 --arguments "" --mode-override patterns)
assert_mode "--mode-override patterns → LIGHT-INLINE" "LIGHT-INLINE" "$MODE"

MODE=$(echo "src/main.rs" | bash "$CLASSIFY" --commit-count 3 --arguments "" --mode-override continue)
assert_mode "--mode-override continue → INSTANT" "INSTANT" "$MODE"

MODE=$(echo "x" | bash "$CLASSIFY" --commit-count 1 --arguments "" --mode-override bogus 2>/dev/null)
RC=$?
TOTAL=$((TOTAL + 1))
if [ "$RC" -eq 2 ]; then
    echo "  PASS: --mode-override bogus → exit 2"
    PASS=$((PASS + 1))
else
    echo "  FAIL: --mode-override bogus → exit $RC (expected 2)"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "Queue-suppression invariant: --patterns NEVER returns plain LIGHT"
for files in "docs/a.md" "src/x.rs" ".claude/settings.json"; do
    MODE=$(classify 1 "$files" "--patterns")
    TOTAL=$((TOTAL + 1))
    if [ "$MODE" = "LIGHT-INLINE" ]; then
        echo "  PASS: --patterns files=$files → LIGHT-INLINE (not LIGHT)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: --patterns files=$files → $MODE (queue suppression broken)"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

[ "$FAIL" -eq 0 ] || exit 1
